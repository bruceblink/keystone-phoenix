defmodule KeystonePhoenixWeb.AdminUserPaginationTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  setup do
    suffix = System.unique_integer([:positive])
    username = "pagination_admin_#{suffix}"
    prefix = "pagination_member_#{suffix}"
    admin_role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    {:ok, admin} =
      %SysUser{}
      |> SysUser.create_changeset(%{
        "username" => username,
        "nickname" => "分页验收管理员",
        "password" => "Strong!123",
        "role_id" => admin_role.role_id,
        "status" => 1
      })
      |> Repo.insert()

    # 使用 21 个同前缀账号稳定构造一条末页记录，测试事务会在用例结束时回滚。
    users =
      Enum.map(1..21, fn number ->
        {:ok, user} =
          %SysUser{}
          |> SysUser.create_changeset(%{
            "username" => "#{prefix}_#{number}",
            "nickname" => "分页验收成员",
            "password" => "Strong!123",
            "status" => 1
          })
          |> Repo.insert()

        user
      end)

    {:ok, admin: admin, prefix: prefix, users: users}
  end

  @tag :integration
  test "deleting the last filtered user returns to the remaining page and updates the URL", %{
    conn: conn,
    admin: admin,
    prefix: prefix,
    users: users
  } do
    {:ok, view, _html} = live(conn, "/")

    render_submit(view, "login", %{
      "username" => admin.username,
      "password" => "Strong!123"
    })

    render_click(view, "show-panel", %{"panel" => "users"})
    render_submit(view, "filter-users", %{"username" => prefix, "displayName" => ""})
    assert live_socket(view).assigns.user_total == 21
    assert length(live_socket(view).assigns.user_rows) == 20

    render_click(view, "paginate", %{"panel" => "users", "page" => "2"})
    assert live_socket(view).assigns.page_nums["users"] == 2
    assert length(live_socket(view).assigns.user_rows) == 1
    assert URI.parse(live_socket(view).assigns.current_uri).query =~ "users_page=2"

    deleted_id = hd(live_socket(view).assigns.user_rows)["userId"]
    render_click(view, "delete-user", %{"user-id" => deleted_id})

    assigns = live_socket(view).assigns
    assert assigns.user_total == 20
    assert length(assigns.user_rows) == 20
    assert assigns.page_nums["users"] == 1

    assert Enum.sort(Enum.map(assigns.user_rows, & &1["userId"])) ==
             users
             |> Enum.map(&to_string(&1.user_id))
             |> Enum.reject(&(&1 == deleted_id))
             |> Enum.sort()

    uri = URI.parse(assigns.current_uri)
    assert uri.path == "/users"
    assert URI.decode_query(uri.query || "") == %{"users_username" => prefix}
    assert render(view) =~ "共 20 个用户"
  end

  defp live_socket(view), do: find_socket(:sys.get_state(view.pid))

  defp find_socket(%Phoenix.LiveView.Socket{} = socket), do: socket
  defp find_socket(%{} = map), do: map |> Map.values() |> Enum.find_value(&find_socket/1)

  defp find_socket(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.find_value(&find_socket/1)

  defp find_socket(list) when is_list(list), do: Enum.find_value(list, &find_socket/1)
  defp find_socket(_value), do: nil
end
