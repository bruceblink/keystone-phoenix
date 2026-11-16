defmodule KeystonePhoenixWeb.AdminDictionaryFilterPaginationTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import KeystonePhoenixWeb.LiveAuthenticationTestSupport, only: [live_socket: 1]

  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  setup do
    username = "dict_filter_admin_#{System.unique_integer([:positive])}"
    admin_role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    {:ok, admin} =
      %SysUser{}
      |> SysUser.create_changeset(%{
        "username" => username,
        "nickname" => "字典筛选管理员",
        "password" => "Strong!123",
        "role_id" => admin_role.role_id,
        "status" => 1
      })
      |> Repo.insert()

    {:ok, admin: admin}
  end

  @tag :integration
  test "dictionary type filtering keeps server-side item pagination", %{conn: conn, admin: admin} do
    dict_type = "live.filter.type.#{System.unique_integer([:positive])}"

    {:ok, _type} =
      Dictionary.create_dict_type(
        %{"dictName" => "筛选分页字典", "dictType" => dict_type, "status" => 1},
        authorization: %{principal: admin}
      )

    Enum.each(1..51, fn index ->
      {:ok, _data} =
        Dictionary.create_dict_data(
          %{
            "dictType" => dict_type,
            "dictLabel" => "筛选值 #{index}",
            "dictValue" => Integer.to_string(index),
            "dictSort" => index,
            "isDefault" => false,
            "status" => 1
          },
          authorization: %{principal: admin}
        )
    end)

    {:ok, view, _html} = live(conn, "/")

    render_submit(view, "login", %{
      "username" => admin.username,
      "password" => "Strong!123"
    })

    render_click(view, "show-panel", %{"panel" => "dicts"})
    render_click(view, "select-dict-type", %{"dict-type" => dict_type})
    render_submit(view, "filter-dict-types", %{"dictTypeKeyword" => dict_type})

    assert live_socket(view).assigns.selected_dict_type == dict_type
    assert live_socket(view).assigns.dict_data_total == 51
    assert length(live_socket(view).assigns.dict_data_rows) == 50
    assert live_socket(view).assigns.page_nums["dict-data"] == 1
  end
end
