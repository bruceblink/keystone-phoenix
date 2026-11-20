defmodule KeystonePhoenixWeb.UserScopeTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.{Auth, Excel, Permission, Repo, User}
  alias KeystonePhoenix.Auth.Mfa.Totp
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Live.AdminSupport

  setup do
    parent = insert_dept(nil, "")
    child = insert_dept(parent.dept_id, "")
    outside = insert_dept(nil, "")

    role =
      %SysRole{role_id: Identity.v7()}
      |> SysRole.changeset(%{
        role_name: "用户范围测试",
        role_key: unique("scope"),
        role_sort: 1,
        data_scope: "DEPARTMENT_AND_CHILDREN",
        status: 1
      })
      |> Repo.insert!()

    for permission <-
          ~w(user:read user:export user:update user:create user:import user:delete mfa:manage) do
      menu =
        %SysMenu{menu_id: Identity.v7()}
        |> SysMenu.changeset(%{
          menu_name: permission,
          menu_type: 0,
          parent_id: nil,
          status: 1
        })
        |> Repo.insert!()

      entry =
        Repo.get_by(SysPermission, permission: permission) ||
          Repo.insert!(%SysPermission{
            permission: permission,
            permission_id: Identity.permission_id(permission),
            resource: permission |> String.split(":") |> Enum.at(0),
            domain: "default",
            action: permission |> String.split(":") |> List.last(),
            status: 1,
            deprecated: false
          })

      Repo.insert!(%SysRolePermission{role_id: role.role_id, permission_id: entry.permission_id})
      Repo.insert!(%SysRoleMenu{role_id: role.role_id, menu_id: menu.menu_id})
    end

    password_hash = Bcrypt.hash_pwd_salt("Strong!123")
    oldest = insert_user(parent.dept_id, nil, password_hash)
    descendant = insert_user(child.dept_id, nil, password_hash)
    now = DateTime.utc_now()

    outside_rows =
      for _ <- 1..60 do
        %{
          username: unique("scope_user"),
          user_id: Identity.v7(),
          nickname: "范围外测试用户",
          password: password_hash,
          dept_id: outside.dept_id,
          status: 1,
          deleted: false,
          create_time: now,
          update_time: now
        }
      end

    {60, inserted} = Repo.insert_all(SysUser, outside_rows, returning: [:user_id])
    actor = insert_user(parent.dept_id, role.role_id, password_hash)

    {:ok,
     parent: parent,
     child: child,
     outside: outside,
     role: role,
     actor: actor,
     oldest: oldest,
     descendant: descendant,
     outside_ids: Enum.map(inserted, & &1.user_id)}
  end

  test "all five scopes apply before total, filters and pagination", ctx do
    all_ids = [ctx.actor.user_id, ctx.oldest.user_id, ctx.descendant.user_id | ctx.outside_ids]

    cases = [
      {"ALL", "", all_ids},
      {"CUSTOM", "#{ctx.child.dept_id}", [ctx.descendant.user_id]},
      {"DEPARTMENT", "", [ctx.actor.user_id, ctx.oldest.user_id]},
      {"DEPARTMENT_AND_CHILDREN", "",
       [ctx.actor.user_id, ctx.oldest.user_id, ctx.descendant.user_id]},
      {"SELF", "", [ctx.actor.user_id]}
    ]

    for {scope, department_set, expected_ids} <- cases do
      Repo.update!(
        Ecto.Changeset.change(Repo.get!(SysRole, ctx.role.role_id),
          data_scope: scope,
          dept_id_set: department_set
        )
      )

      result = User.list_users(%{"pageSize" => 500, "username" => "scope_user"}, ctx.actor)
      assert result.total == length(expected_ids)
      assert MapSet.new(Enum.map(result.rows, & &1["userId"])) == MapSet.new(expected_ids)

      page =
        User.list_users(%{"pageSize" => 1, "pageNum" => 2, "username" => "scope_user"}, ctx.actor)

      assert page.total == length(expected_ids)
      assert length(page.rows) == min(max(length(expected_ids) - 1, 0), 1)
    end

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(SysRole, ctx.role.role_id),
        data_scope: "DEPARTMENT_AND_CHILDREN"
      )
    )

    result = User.list_users(%{"deptId" => ctx.child.dept_id}, ctx.actor)
    assert Enum.map(result.rows, & &1["userId"]) == [ctx.descendant.user_id]
    assert User.list_users(%{"deptId" => ctx.outside.dept_id}, ctx.actor).total == 0

    rows = AdminSupport.load_users_for_user(User.user_to_map(ctx.actor))
    assert ctx.oldest.user_id in Enum.map(rows, & &1["userId"])
    assert length(rows) == 3
  end

  @tag :integration
  test "HTTP list, detail and export expose the same authorized set", ctx do
    {:ok, tokens} = Auth.login_plaintext(ctx.actor.username, "Strong!123")
    response = get(authorized(tokens.token), "/api/v1/users", %{"pageSize" => 50})
    response_data = json_response(response, 200)["data"]
    assert %{"total" => 3, "items" => rows} = response_data
    refute Map.has_key?(response_data, "rows")
    expected = MapSet.new([ctx.actor.user_id, ctx.oldest.user_id, ctx.descendant.user_id])
    assert MapSet.new(Enum.map(rows, & &1["id"])) == expected

    expected_page_order = expected |> MapSet.to_list() |> Enum.sort()

    paged_ids =
      for page <- [1, 2], reduce: [] do
        ids ->
          response =
            get(authorized(tokens.token), "/api/v1/users", %{
              "username" => "scope_user",
              "page" => to_string(page),
              "size" => "2"
            })
            |> json_response(200)
            |> get_in(["data"])

          assert response["page"] == page
          assert response["size"] == 2
          assert response["total"] == length(expected_page_order)
          ids ++ Enum.map(response["items"], & &1["id"])
      end

    assert paged_ids == expected_page_order
    assert length(Enum.uniq(paged_ids)) == length(expected_page_order)

    assert json_response(
             get(authorized(tokens.token), "/api/v1/users/#{ctx.oldest.user_id}"),
             200
           )["data"]["id"] == ctx.oldest.user_id

    assert json_response(
             get(authorized(tokens.token), "/api/v1/users/#{hd(ctx.outside_ids)}"),
             403
           )["error"]["code"] == "data_scope_denied"

    response = get(authorized(tokens.token), "/api/v1/users/export")
    assert response.status == 200
    path = Path.join(System.tmp_dir!(), "#{unique("user_scope")}.xlsx")
    File.write!(path, response.resp_body)
    on_exit(fn -> File.rm(path) end)
    assert {:ok, [_headers | exported]} = Excel.import_rows(path)
    assert MapSet.new(Enum.map(exported, &hd/1)) == expected
  end

  @tag :integration
  test "writes check both the original user and the destination department", ctx do
    token = step_up_token(ctx.actor)

    response =
      put(authorized(token), "/api/v1/users/#{ctx.oldest.user_id}", %{
        "deptId" => ctx.outside.dept_id,
        "nickname" => "不应写入"
      })

    assert get_in(json_response(response, 403), ["error", "code"]) == "data_scope_denied"
    assert Repo.get!(SysUser, ctx.oldest.user_id).dept_id == ctx.parent.dept_id
    refute Repo.get!(SysUser, ctx.oldest.user_id).nickname == "不应写入"

    response =
      put(authorized(token), "/api/v1/users/#{hd(ctx.outside_ids)}", %{
        "deptId" => ctx.parent.dept_id
      })

    assert get_in(json_response(response, 403), ["error", "code"]) == "data_scope_denied"

    response =
      put(authorized(token), "/api/v1/users/#{ctx.oldest.user_id}", %{
        "deptId" => ctx.child.dept_id
      })

    assert json_response(response, 200)["success"] == true
    assert Repo.get!(SysUser, ctx.oldest.user_id).dept_id == ctx.child.dept_id

    denied_name = unique("denied_create")

    response =
      post(authorized(token), "/api/v1/users", %{
        "username" => denied_name,
        "password" => "Strong!123",
        "deptId" => ctx.outside.dept_id
      })

    assert get_in(json_response(response, 403), ["error", "code"]) == "data_scope_denied"
    assert {:error, :not_found} = User.get_user_by_username(denied_name)

    allowed_name = unique("allowed_create")

    response =
      post(authorized(token), "/api/v1/users", %{
        "username" => allowed_name,
        "password" => "Strong!123",
        "displayName" => "允许创建用户",
        "deptId" => ctx.child.dept_id
      })

    assert json_response(response, 201)["success"] == true
    assert {:ok, created} = User.get_user_by_username(allowed_name)
    assert created.dept_id == ctx.child.dept_id
  end

  @tag :integration
  test "user create follows the Native policy-disabled MFA behavior", ctx do
    {:ok, tokens} = Auth.login_plaintext(ctx.actor.username, "Strong!123")
    username = unique("policy_disabled_create")

    response =
      post(authorized(tokens.token), "/api/v1/users", %{
        "username" => username,
        "password" => "Strong!123",
        "displayName" => "策略允许创建用户",
        "deptId" => ctx.child.dept_id
      })

    assert json_response(response, 201)["success"] == true
    {:ok, created} = User.get_user_by_username(username)

    rejected_username = unique("policy_rejected_create")

    rejected =
      post(authorized(tokens.token), "/api/v1/users", %{
        "username" => rejected_username,
        "password" => "test-only-disallowed",
        "displayName" => "策略拒绝用户",
        "deptId" => ctx.child.dept_id
      })

    assert get_in(json_response(rejected, 422), ["error", "code"]) == "password_disallowed"
    assert {:error, :not_found} = User.get_user_by_username(rejected_username)

    on_exit(fn ->
      Repo.update!(Ecto.Changeset.change(Repo.get!(SysUser, created.user_id), deleted: true))
    end)
  end

  @tag :integration
  test "self scope can list and edit itself but cannot move to another department", ctx do
    Repo.update!(Ecto.Changeset.change(ctx.role, data_scope: "SELF"))
    token = step_up_token(ctx.actor)
    response = get(authorized(token), "/api/v1/users")
    response_data = json_response(response, 200)["data"]
    assert %{"total" => 1, "items" => [row]} = response_data
    refute Map.has_key?(response_data, "rows")
    assert row["id"] == ctx.actor.user_id

    response =
      put(authorized(token), "/api/v1/users/#{ctx.actor.user_id}", %{
        "nickname" => "本人已更新",
        "deptId" => ctx.actor.dept_id
      })

    assert json_response(response, 200)["success"] == true

    response =
      put(authorized(token), "/api/v1/users/#{ctx.actor.user_id}", %{
        "deptId" => ctx.child.dept_id
      })

    assert get_in(json_response(response, 403), ["error", "code"]) == "data_scope_denied"
    assert Repo.get!(SysUser, ctx.actor.user_id).dept_id == ctx.actor.dept_id
  end

  @tag :integration
  test "HTTP user batch delete rolls back invalid targets and revokes only committed sessions",
       ctx do
    actor_token = step_up_token(ctx.actor)
    {:ok, target_tokens} = Auth.login_plaintext(ctx.oldest.username, "Strong!123")
    missing_id = Identity.v7()

    response =
      delete(
        authorized(actor_token),
        "/api/v1/users?ids=#{ctx.oldest.user_id},#{missing_id}",
        %{}
      )

    assert response.status == 404
    assert json_response(response, 404)["error"]["code"] == "resource_not_found"
    assert {:ok, _user} = User.get_user(ctx.oldest.user_id)
    assert {:ok, _session} = Auth.session_context(target_tokens.token)

    response =
      delete(
        authorized(actor_token),
        "/api/v1/users?ids=#{ctx.oldest.user_id},#{hd(ctx.outside_ids)}",
        %{}
      )

    assert response.status == 403
    assert json_response(response, 403)["error"]["code"] == "data_scope_denied"
    assert {:ok, _user} = User.get_user(ctx.oldest.user_id)

    response =
      delete(
        authorized(actor_token),
        "/api/v1/users/#{ctx.oldest.user_id}",
        %{}
      )

    assert json_response(response, 200)["success"] == true
    assert {:error, :not_found} = User.get_user(ctx.oldest.user_id)
    assert {:error, :invalid_token} = Auth.session_context(target_tokens.token)
  end

  @tag :integration
  test "non-admin users cannot assign roles through create or update", ctx do
    elevated_role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: unique("elevated_role"),
        role_key: unique("elevated_role_key"),
        role_sort: 1,
        data_scope: "ALL",
        status: 1
      })
      |> Repo.insert!()

    token = step_up_token(ctx.actor)

    response =
      post(authorized(token), "/api/v1/users", %{
        "username" => unique("role_denied_create"),
        "password" => "Strong!123",
        "deptId" => ctx.child.dept_id,
        "roleId" => elevated_role.role_id
      })

    assert get_in(json_response(response, 403), ["error", "code"]) == "permission_denied"

    response =
      put(authorized(token), "/api/v1/users/#{ctx.actor.user_id}", %{
        "nickname" => "角色不应改变",
        "deptId" => ctx.actor.dept_id,
        "roleId" => elevated_role.role_id
      })

    assert get_in(json_response(response, 403), ["error", "code"]) == "permission_denied"
    assert Repo.get!(SysUser, ctx.actor.user_id).role_id == ctx.role.role_id
  end

  test "inactive or missing roles expose no users, while administrator access remains unchanged",
       ctx do
    Repo.update!(Ecto.Changeset.change(ctx.role, status: 0))
    assert User.list_users(%{}, ctx.actor).total == 0
    assert User.list_users(%{}, %{ctx.actor | role_id: nil}).total == 0

    assert User.list_users(%{"pageSize" => 500, "username" => "scope_user"}, ctx.actor).total == 0

    refute Permission.user_update_allowed?(ctx.actor, ctx.oldest.user_id, %{})
  end

  @tag :integration
  test "multipart import uses the client filename and checks each row scope", ctx do
    {:ok, tokens} = Auth.login_plaintext(ctx.actor.username, "Strong!123")

    allowed_username = unique("import_allowed")
    denied_username = unique("import_denied")
    invalid_format_username = "invalid-format-#{System.unique_integer([:positive])}"
    bad_password_username = unique("import_bad_password")

    {:ok, workbook} =
      Excel.export(
        ["部门ID", "用户名", "密码", "状态", "角色ID"],
        [
          [ctx.child.dept_id, allowed_username, "Strong!123", 1, nil],
          [ctx.outside.dept_id, denied_username, "Strong!123", 1, nil],
          [ctx.parent.dept_id, ctx.actor.username, "Strong!123", 1, nil],
          [ctx.parent.dept_id, invalid_format_username, "Strong!123", 1, nil],
          [ctx.parent.dept_id, bad_password_username, "test-only-disallowed", 1, nil]
        ],
        "users.xlsx"
      )

    path = Path.join(System.tmp_dir!(), unique("multipart_upload"))
    File.write!(path, workbook)
    on_exit(fn -> File.rm(path) end)

    upload = %Plug.Upload{
      path: path,
      filename: "users.xlsx",
      content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    }

    response = post(authorized(tokens.token), "/api/v1/users/import", %{"file" => upload})
    assert get_in(json_response(response, 403), ["error", "code"]) == "mfa_step_up_required"

    # 通过真实 HTTP TOTP enrollment 和 step-up 流程获取短时 AAL2 访问令牌。
    enrollment =
      build_conn()
      |> put_req_header("authorization", "Bearer #{tokens.token}")
      |> post("/api/v1/auth/mfa/enroll", %{})
      |> json_response(201)

    secret = enrollment["data"]["secret"]
    enrollment_now = System.system_time(:second)

    enrollment_verification =
      build_conn()
      |> put_req_header("authorization", "Bearer #{tokens.token}")
      |> post("/api/v1/auth/mfa/enroll/verify", %{
        "challengeId" => enrollment["data"]["challengeId"],
        "code" => Totp.code(secret, enrollment_now)
      })
      |> json_response(200)

    assert enrollment_verification["data"]["authenticationLevel"] == "AAL2"

    # enrollment 会递增 permission_version，重新建立一个有效的 AAL1 会话。
    {:ok, step_up_tokens} = Auth.login_plaintext(ctx.actor.username, "Strong!123", true)

    step_up_challenge =
      build_conn()
      |> put_req_header("authorization", "Bearer #{step_up_tokens.token}")
      |> post("/api/v1/auth/mfa/step-up", %{})
      |> json_response(201)

    step_up =
      build_conn()
      |> put_req_header("authorization", "Bearer #{step_up_tokens.token}")
      |> post("/api/v1/auth/mfa/step-up/verify", %{
        "challengeId" => step_up_challenge["data"]["challengeId"],
        "code" => Totp.code(secret, enrollment_now + Totp.step_seconds())
      })
      |> json_response(200)

    assert step_up["data"]["authenticationLevel"] == "AAL2"

    response =
      post(authorized(step_up["data"]["accessToken"]), "/api/v1/users/import", %{
        "file" => upload
      })

    assert %{
             "data" => %{
               "success" => 1,
               "failed" => [
                 scope_failure,
                 duplicate_failure,
                 username_format_failure,
                 password_failure
               ]
             }
           } =
             json_response(response, 200)

    assert scope_failure["row"] == 3
    assert scope_failure["username"] == denied_username
    assert scope_failure["reason"] == "没有数据权限"
    assert scope_failure["code"] == "data_scope_denied"
    assert is_binary(scope_failure["reason"])
    assert duplicate_failure["row"] == 4
    assert duplicate_failure["username"] == ctx.actor.username
    assert duplicate_failure["reason"] == "username already exists"
    assert duplicate_failure["code"] == "username_already_exists"
    assert is_binary(duplicate_failure["reason"])
    assert username_format_failure["row"] == 5
    assert username_format_failure["username"] == invalid_format_username
    assert username_format_failure["code"] == "username_invalid_format"
    assert password_failure["row"] == 6
    assert password_failure["username"] == bad_password_username
    assert password_failure["code"] == "password_disallowed"
    assert is_binary(password_failure["reason"])
    assert {:ok, imported} = User.get_user_by_username(allowed_username)
    assert imported.dept_id == ctx.child.dept_id
    assert {:error, :not_found} = User.get_user_by_username(denied_username)
    assert {:error, :not_found} = User.get_user_by_username(bad_password_username)
  end

  defp authorized(token), do: put_req_header(build_conn(), "authorization", "Bearer #{token}")

  defp insert_dept(parent_id, _ancestors) do
    parent_id = if parent_id in [0, "0"], do: nil, else: parent_id

    ancestors =
      case parent_id do
        nil ->
          ""

        parent_id ->
          parent = Repo.get!(SysDept, parent_id)
          Enum.join([parent.ancestors, parent.dept_id], ",") |> String.trim_leading(",")
      end

    %SysDept{dept_id: Identity.v7()}
    |> SysDept.changeset(%{
      parent_id: parent_id,
      ancestors: ancestors,
      dept_name: unique("department"),
      status: 1
    })
    |> Repo.insert!()
  end

  defp insert_user(dept_id, role_id, password_hash) do
    Repo.insert!(%SysUser{
      user_id: Identity.v7(),
      username: unique("scope_user"),
      nickname: "范围测试用户",
      password: password_hash,
      dept_id: dept_id,
      role_id: role_id,
      status: 1
    })
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
