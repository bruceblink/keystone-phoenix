defmodule KeystonePhoenixWeb.UserScopeTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.{Auth, Excel, Permission, Repo, User}
  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Live.AdminSupport

  setup do
    parent = insert_dept(0, "0")
    child = insert_dept(parent.dept_id, "0,#{parent.dept_id}")
    outside = insert_dept(0, "0")

    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: "用户范围测试",
        role_key: unique("scope"),
        role_sort: 1,
        data_scope: 4,
        status: 1
      })
      |> Repo.insert!()

    for permission <-
          ~w(system:user:list system:user:query system:user:export system:user:edit system:user:add) do
      menu =
        %SysMenu{}
        |> SysMenu.changeset(%{
          menu_name: permission,
          menu_type: 0,
          parent_id: 0,
          permission: permission,
          status: 1
        })
        |> Repo.insert!()

      Repo.insert!(%SysRoleMenu{role_id: role.role_id, menu_id: menu.menu_id})
    end

    password_hash = Bcrypt.hash_pwd_salt("Strong!123")
    oldest = insert_user(parent.dept_id, nil, password_hash)
    descendant = insert_user(child.dept_id, nil, password_hash)
    now = DateTime.utc_now()

    outside_rows =
      for _ <- 1..60 do
        %{
          username: unique("outside"),
          nickname: "范围外测试用户",
          password: password_hash,
          dept_id: outside.dept_id,
          status: 1,
          is_admin: false,
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
      {1, "", all_ids},
      {2, "#{ctx.child.dept_id}", [ctx.descendant.user_id]},
      {3, "", [ctx.actor.user_id, ctx.oldest.user_id]},
      {4, "", [ctx.actor.user_id, ctx.oldest.user_id, ctx.descendant.user_id]},
      {5, "", [ctx.actor.user_id]}
    ]

    for {scope, department_set, expected_ids} <- cases do
      Repo.update!(
        Ecto.Changeset.change(Repo.get!(SysRole, ctx.role.role_id),
          data_scope: scope,
          dept_id_set: department_set
        )
      )

      result = User.list_users(%{"pageSize" => 500}, ctx.actor)
      assert result.total == length(expected_ids)
      assert MapSet.new(Enum.map(result.rows, & &1["userId"])) == MapSet.new(expected_ids)

      page = User.list_users(%{"pageSize" => 1, "pageNum" => 2}, ctx.actor)
      assert page.total == length(expected_ids)
      assert length(page.rows) == min(max(length(expected_ids) - 1, 0), 1)
    end

    Repo.update!(Ecto.Changeset.change(Repo.get!(SysRole, ctx.role.role_id), data_scope: 4))
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
    response = get(authorized(tokens.token), "/system/users", %{"pageSize" => 50})
    assert %{"data" => %{"total" => 3, "rows" => rows}} = json_response(response, 200)
    expected = MapSet.new([ctx.actor.user_id, ctx.oldest.user_id, ctx.descendant.user_id])
    assert MapSet.new(Enum.map(rows, & &1["userId"])) == expected

    assert json_response(
             get(authorized(tokens.token), "/system/users/#{ctx.oldest.user_id}"),
             200
           )["data"]["userId"] == ctx.oldest.user_id

    assert json_response(
             get(authorized(tokens.token), "/system/users/#{hd(ctx.outside_ids)}"),
             403
           )["code"] == 40303

    response = get(authorized(tokens.token), "/system/users/excel")
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
      put(authorized(tokens.token), "/system/users/#{ctx.oldest.user_id}", %{
        "deptId" => ctx.outside.dept_id,
        "nickname" => "不应写入"
      })

    assert json_response(response, 403)["code"] == 40303
    assert Repo.get!(SysUser, ctx.oldest.user_id).dept_id == ctx.parent.dept_id
    refute Repo.get!(SysUser, ctx.oldest.user_id).nickname == "不应写入"

    response =
      put(authorized(tokens.token), "/system/users/#{hd(ctx.outside_ids)}", %{
        "deptId" => ctx.parent.dept_id
      })

    assert json_response(response, 403)["code"] == 40303

    response =
      put(authorized(tokens.token), "/system/users/#{ctx.oldest.user_id}", %{
        "deptId" => ctx.child.dept_id
      })

    assert json_response(response, 200)["code"] == 0
    assert Repo.get!(SysUser, ctx.oldest.user_id).dept_id == ctx.child.dept_id

    denied_name = unique("denied_create")

    response =
      post(authorized(tokens.token), "/system/users", %{
        "username" => denied_name,
        "password" => "Strong!123",
        "deptId" => ctx.outside.dept_id
      })

    assert json_response(response, 403)["code"] == 40303
    assert {:error, :not_found} = User.get_user_by_username(denied_name)

    allowed_name = unique("allowed_create")

    response =
      post(authorized(tokens.token), "/system/users", %{
        "username" => allowed_name,
        "password" => "Strong!123",
        "deptId" => ctx.child.dept_id
      })

    assert json_response(response, 201)["code"] == 0
    assert {:ok, created} = User.get_user_by_username(allowed_name)
    assert created.dept_id == ctx.child.dept_id
  end

  @tag :integration
  test "self scope can list and edit itself but cannot move to another department", ctx do
    Repo.update!(Ecto.Changeset.change(ctx.role, data_scope: 5))
    {:ok, tokens} = Auth.login_plaintext(ctx.actor.username, "Strong!123")
    response = get(authorized(tokens.token), "/system/users")
    assert %{"data" => %{"total" => 1, "rows" => [row]}} = json_response(response, 200)
    assert row["userId"] == ctx.actor.user_id

    response =
      put(authorized(tokens.token), "/system/users/#{ctx.actor.user_id}", %{
        "nickname" => "本人已更新",
        "deptId" => ctx.actor.dept_id
      })

    assert json_response(response, 200)["code"] == 0

    response =
      put(authorized(tokens.token), "/system/users/#{ctx.actor.user_id}", %{
        "deptId" => ctx.child.dept_id
      })

    assert json_response(response, 403)["code"] == 40303
    assert Repo.get!(SysUser, ctx.actor.user_id).dept_id == ctx.actor.dept_id
  end

  test "inactive or missing roles expose no users, while administrator access remains unchanged",
       ctx do
    Repo.update!(Ecto.Changeset.change(ctx.role, status: 0))
    assert User.list_users(%{}, ctx.actor).total == 0
    assert User.list_users(%{}, %{ctx.actor | role_id: nil}).total == 0
    assert User.list_users(%{"pageSize" => 500}, %{ctx.actor | is_admin: true}).total == 63
    refute Permission.user_update_allowed?(ctx.actor, ctx.oldest.user_id, %{})
  end

  defp authorized(token), do: put_req_header(build_conn(), "authorization", "Bearer #{token}")

  defp insert_dept(parent_id, ancestors) do
    %SysDept{}
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
