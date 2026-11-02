defmodule KeystonePhoenix.Menu do
  @moduledoc "Query boundary for menu and permission management."

  import Ecto.Query

  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Repo

  def list_menus(params \\ %{}) do
    query =
      from(m in SysMenu,
        where: m.deleted == false,
        order_by: [asc: m.parent_id, asc: m.menu_id]
      )

    query = filter_status(query, params["status"] || params[:status])
    query = filter_type(query, params["menuType"] || params[:menu_type])
    Repo.all(query) |> Enum.map(&menu_to_map/1)
  end

  def list_dropdown do
    list_menus(%{"status" => 1})
  end

  def get_menu(id) do
    case Repo.get_by(SysMenu, menu_id: id, deleted: false) do
      nil -> {:error, :not_found}
      menu -> {:ok, menu}
    end
  end

  def menus_for_user(user) do
    query =
      from(m in SysMenu,
        join: rm in "sys_role_menu",
        on: rm.menu_id == m.menu_id,
        join: role in "sys_role",
        on: role.role_id == rm.role_id,
        where:
          m.deleted == false and m.status == 1 and role.deleted == false and role.status == 1 and
            rm.role_id == ^user.role_id,
        order_by: [asc: m.parent_id, asc: m.menu_id],
        distinct: true
      )

    if user.is_admin do
      list_menus(%{"status" => 1})
    else
      Repo.all(query) |> Enum.map(&menu_to_map/1)
    end
  end

  @doc "Builds the authenticated user's router tree."
  def routers_for_user(user) do
    menus_for_user(user)
    |> Enum.reject(&(&1["isButton"] == 1))
    |> build_tree()
  end

  def menu_to_map(menu) do
    %{
      "menuId" => menu.menu_id,
      "menuName" => menu.menu_name,
      "menuType" => menu.menu_type,
      "routerName" => menu.router_name,
      "parentId" => menu.parent_id,
      "path" => menu.path,
      "isButton" => if(menu.is_button, do: 1, else: 0),
      "permission" => menu.permission,
      "meta" => decode_meta(menu.meta_info),
      "status" => menu.status,
      "remark" => menu.remark,
      "createTime" => format_datetime(menu.create_time)
    }
  end

  defp build_tree(menus) do
    Enum.filter(menus, &(&1["parentId"] == 0))
    |> Enum.map(&attach_children(&1, menus))
  end

  defp attach_children(menu, menus) do
    children =
      menus
      |> Enum.filter(&(&1["parentId"] == menu["menuId"]))
      |> Enum.map(&attach_children(&1, menus))

    if children == [], do: menu, else: Map.put(menu, "children", children)
  end

  defp filter_status(query, nil), do: query
  defp filter_status(query, ""), do: query

  defp filter_status(query, value) do
    case Integer.parse(to_string(value)) do
      {status, ""} -> where(query, [menu], menu.status == ^status)
      _ -> query
    end
  end

  defp filter_type(query, nil), do: query
  defp filter_type(query, ""), do: query

  defp filter_type(query, value) do
    case Integer.parse(to_string(value)) do
      {menu_type, ""} -> where(query, [menu], menu.menu_type == ^menu_type)
      _ -> query
    end
  end

  defp decode_meta(meta_info) when is_binary(meta_info) do
    case Jason.decode(meta_info) do
      {:ok, meta} -> meta
      _ -> %{}
    end
  end

  defp decode_meta(_meta_info), do: %{}

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
