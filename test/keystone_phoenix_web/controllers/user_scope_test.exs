defmodule KeystonePhoenixWeb.UserScopeTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.{Auth, Excel, Permission, Repo, User}
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
          ~w(user:read user:export user:update user:create user:import) do
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
    response = get(authorized(tokens.token), "/api/v1/system/users", %{"pageSize" => 50})
    assert %{"data" => %{"total" => 3, "rows" => rows}} = json_response(response, 200)
    expected = MapSet.new([ctx.actor.user_id, ctx.oldest.user_id, ctx.descendant.user_id])
    assert MapSet.new(Enum.map(rows, & &1["userId"])) == expected

    assert json_response(
             get(authorized(tokens.token), "/api/v1/system/users/#{ctx.oldest.user_id}"),
             200
           )["data"]["userId"] == ctx.oldest.user_id

    assert json_response(
             get(authorized(tokens.token), "/api/v1/system/users/#{hd(ctx.outside_ids)}"),
             403
           )["error"]["code"] == "data_scope_denied"

    response = get(authorized(tokens.token), "/api/v1/system/users/excel")
    assert response.status == 200
    path = Path.join(System.tmp_dir!(), "#{unique("user_scope")}.xlsx")
    File.write!(path, response.resp_body)
    on_exit(fn -> File.rm(path) end)
    assert {:ok, [_headers | exported]} = Excel.import_rows(path)
    assert MapSet.new(Enum.map(exported, &hd/1)) == expected
  end

  @tag :integration
  test "writes check both the original user and the destination department", ctx do
    {:ok, tokens} = Auth.login_plaintext(ctx.actor.username, "Strong!123")

    response =
      put(authorized(tokens.token), "/api/v1/system/users/#{ctx.oldest.user_id}", %{
        "deptId" => ctx.outside.dept_id,
        "nickname" => "不应写入"
      })

    assert get_in(json_response(response, 403), ["error", "code"]) == "data_scope_denied"
    assert Repo.get!(SysUser, ctx.oldest.user_id).dept_id == ctx.parent.dept_id
    refute Repo.get!(SysUser, ctx.oldest.user_id).nickname == "不应写入"

    response =
      put(authorized(tokens.token), "/api/v1/system/users/#{hd(ctx.outside_ids)}", %{
        "deptId" => ctx.parent.dept_id
      })

    assert get_in(json_response(response, 403), ["error", "code"]) == "data_scope_denied"

    response =
      put(authorized(tokens.token), "/api/v1/system/users/#{ctx.oldest.user_id}", %{
        "deptId" => ctx.child.dept_id
      })

    assert json_response(response, 200)["success"] == true
    assert Repo.get!(SysUser, ctx.oldest.user_id).dept_id == ctx.child.dept_id

    denied_name = unique("denied_create")

    response =
      post(authorized(tokens.token), "/api/v1/system/users", %{
        "username" => denied_name,
        "password" => "Strong!123",
        "deptId" => ctx.outside.dept_id
      })

    assert get_in(json_response(response, 403), ["error", "code"]) == "data_scope_denied"
    assert {:error, :not_found} = User.get_user_by_username(denied_name)

    allowed_name = unique("allowed_create")

    response =
      post(authorized(tokens.token), "/api/v1/system/users", %{
        "username" => allowed_name,
        "password" => "Strong!123",
        "deptId" => ctx.child.dept_id
      })

    assert json_response(response, 201)["success"] == true
    assert {:ok, created} = User.get_user_by_username(allowed_name)
    assert created.dept_id == ctx.child.dept_id
  end

  @tag :integration
  test "self scope can list and edit itself but cannot move to another department", ctx do
    Repo.update!(Ecto.Changeset.change(ctx.role, data_scope: "SELF"))
    {:ok, tokens} = Auth.login_plaintext(ctx.actor.username, "Strong!123")
    response = get(authorized(tokens.token), "/api/v1/system/users")
    assert %{"data" => %{"total" => 1, "rows" => [row]}} = json_response(response, 200)
    assert row["userId"] == ctx.actor.user_id

    response =
      put(authorized(tokens.token), "/api/v1/system/users/#{ctx.actor.user_id}", %{
        "nickname" => "本人已更新",
        "deptId" => ctx.actor.dept_id
      })

    assert json_response(response, 200)["success"] == true

    response =
      put(authorized(tokens.token), "/api/v1/system/users/#{ctx.actor.user_id}", %{
        "deptId" => ctx.child.dept_id
      })

    assert get_in(json_response(response, 403), ["error", "code"]) == "data_scope_denied"
    assert Repo.get!(SysUser, ctx.actor.user_id).dept_id == ctx.actor.dept_id
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

    {:ok, tokens} = Auth.login_plaintext(ctx.actor.username, "Strong!123")

    response =
      post(authorized(tokens.token), "/api/v1/system/users", %{
        "username" => unique("role_denied_create"),
        "password" => "Strong!123",
        "deptId" => ctx.child.dept_id,
        "roleId" => elevated_role.role_id
      })

    assert get_in(json_response(response, 403), ["error", "code"]) == "permission_denied"

    response =
      put(authorized(tokens.token), "/api/v1/system/users/#{ctx.actor.user_id}", %{
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

    {:ok, workbook} =
      Excel.export(
        ["部门ID", "用户名", "密码", "状态", "角色ID"],
        [
          [ctx.child.dept_id, unique("import_allowed"), "Strong!123", 1, nil],
          [ctx.outside.dept_id, unique("import_denied"), "Strong!123", 1, nil]
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

    response = post(authorized(tokens.token), "/api/v1/system/users/excel", %{"file" => upload})
    assert get_in(json_response(response, 403), ["error", "code"]) == "permission_denied"

    :ok = Auth.logout(tokens.refresh_token)
    {:ok, aal2_tokens} = Auth.login_passkey_user(ctx.actor.user_id)

    response =
      post(authorized(aal2_tokens.token), "/api/v1/system/users/excel", %{"file" => upload})

    assert %{"data" => %{"success" => 1, "failed" => [failure]}} = json_response(response, 200)
    assert failure["reason"] == "没有数据权限"
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
