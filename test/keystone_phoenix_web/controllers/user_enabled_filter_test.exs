defmodule KeystonePhoenixWeb.UserEnabledFilterTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}
  alias KeystonePhoenix.User.SysUser

  @password "Strong!123"

  setup do
    role =
      %SysRole{role_id: Identity.v7()}
      |> SysRole.changeset(%{
        role_name: "用户状态筛选测试",
        role_key: unique("enabled_filter_role"),
        role_sort: 1,
        data_scope: "ALL",
        status: 1
      })
      |> Repo.insert!()

    for permission <- ["user:read", "user:export"] do
      menu =
        %SysMenu{menu_id: Identity.v7()}
        |> SysMenu.changeset(%{menu_name: unique("enabled_filter_menu"), menu_type: 0, status: 1})
        |> Repo.insert!()

      entry =
        Repo.get_by(SysPermission, permission: permission) ||
          Repo.insert!(%SysPermission{
            permission_id: Identity.permission_id(permission),
            permission: permission,
            resource: "user",
            domain: "default",
            action: List.last(String.split(permission, ":")),
            status: 1,
            deprecated: false
          })

      Repo.insert!(%SysRolePermission{role_id: role.role_id, permission_id: entry.permission_id})
      Repo.insert!(%SysRoleMenu{role_id: role.role_id, menu_id: menu.menu_id})
    end

    PolicyCache.invalidate()

    username_prefix = unique("enabled_filter")
    password_hash = Bcrypt.hash_pwd_salt(@password)
    actor = insert_user(unique("enabled_filter_actor"), role.role_id, password_hash, 1)
    active = insert_user("#{username_prefix}_active", role.role_id, password_hash, 1)
    disabled = insert_user("#{username_prefix}_disabled", role.role_id, password_hash, 0)

    {:ok,
     actor: actor,
     username_prefix: username_prefix,
     active_id: active.user_id,
     disabled_id: disabled.user_id}
  end

  @tag :integration
  test "HTTP list and export apply Native enabled filters and keep status-only queries", ctx do
    {:ok, tokens} = Auth.login_plaintext(ctx.actor.username, @password)

    active = list_users(tokens.token, %{"username" => ctx.username_prefix, "enabled" => "true"})
    assert active["total"] == 1
    assert [%{"id" => id, "enabled" => true}] = active["items"]
    assert id == ctx.active_id

    disabled =
      list_users(tokens.token, %{"username" => ctx.username_prefix, "enabled" => "false"})

    assert disabled["total"] == 1
    assert [%{"id" => id, "enabled" => false}] = disabled["items"]
    assert id == ctx.disabled_id

    # Native 的 Boolean 查询会忽略大小写；非 true 字符串按 false 处理。
    assert list_users(tokens.token, %{"username" => ctx.username_prefix, "enabled" => "TrUe"})[
             "items"
           ]
           |> Enum.map(& &1["id"]) == [ctx.active_id]

    assert list_users(tokens.token, %{"username" => ctx.username_prefix, "enabled" => "not-true"})[
             "items"
           ]
           |> Enum.map(& &1["id"]) == [ctx.disabled_id]

    # 空 enabled 在 Native 表示没有状态筛选；旧 status 仅在 enabled 缺失时继续生效。
    unfiltered =
      list_users(tokens.token, %{
        "username" => ctx.username_prefix,
        "enabled" => "",
        "status" => "1"
      })

    assert unfiltered["total"] == 2

    legacy_status =
      list_users(tokens.token, %{"username" => ctx.username_prefix, "status" => "1"})

    assert legacy_status["total"] == 1

    # Native 不识别 status，所以同时传入时以 enabled 为准。
    conflict =
      list_users(tokens.token, %{
        "username" => ctx.username_prefix,
        "enabled" => "false",
        "status" => "1"
      })

    assert conflict["total"] == 1
    assert hd(conflict["items"])["id"] == ctx.disabled_id

    assert export_ids(tokens.token, %{"username" => ctx.username_prefix, "enabled" => "true"}) ==
             MapSet.new([ctx.active_id])

    assert export_ids(tokens.token, %{"username" => ctx.username_prefix, "enabled" => "false"}) ==
             MapSet.new([ctx.disabled_id])

    assert export_ids(tokens.token, %{"username" => ctx.username_prefix, "enabled" => "invalid"}) ==
             MapSet.new([ctx.disabled_id])

    assert export_ids(tokens.token, %{
             "username" => ctx.username_prefix,
             "enabled" => "",
             "status" => "1"
           }) == MapSet.new([ctx.active_id, ctx.disabled_id])

    assert export_ids(tokens.token, %{"username" => ctx.username_prefix}) ==
             MapSet.new([ctx.active_id, ctx.disabled_id])
  end

  defp list_users(token, params) do
    get(authorized(token), "/api/v1/users", Map.put(params, "size", "20"))
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp export_ids(token, params) do
    response = get(authorized(token), "/api/v1/users/export", params)
    assert response.status == 200

    path = Path.join(System.tmp_dir!(), "#{unique("enabled_filter")}.xlsx")

    try do
      File.write!(path, response.resp_body)
      assert {:ok, [_headers | rows]} = Excel.import_rows(path)
      MapSet.new(Enum.map(rows, &hd/1))
    after
      File.rm(path)
    end
  end

  defp authorized(token), do: put_req_header(build_conn(), "authorization", "Bearer #{token}")

  defp insert_user(username, role_id, password_hash, status) do
    Repo.insert!(%SysUser{
      user_id: Identity.v7(),
      username: username,
      password: password_hash,
      nickname: "用户状态筛选测试",
      role_id: role_id,
      status: status
    })
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
