defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleSelection do
  @moduledoc "角色列表的当前结果集选择事件。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminPages.OrganizationFilters

  def handle_event(
        "toggle-role-selection",
        %{"role-id" => role_id, "selected" => selected},
        socket
      ) do
    selected_ids = Map.get(socket.assigns, :selected_role_ids, [])

    selected_ids =
      if selected == "true",
        do: Enum.uniq([role_id | selected_ids]),
        else: List.delete(selected_ids, role_id)

    {:noreply, assign(socket, selected_role_ids: selected_ids)}
  end

  def handle_event("toggle-all-role-selection", %{"selected" => selected}, socket) do
    role_ids =
      socket.assigns.role_rows
      |> OrganizationFilters.filtered_roles(socket.assigns[:role_filter])
      |> Enum.map(&to_string(&1["roleId"]))

    selected_ids = Map.get(socket.assigns, :selected_role_ids, [])

    selected_ids =
      if selected == "true",
        do: Enum.uniq(selected_ids ++ role_ids),
        else: selected_ids -- role_ids

    {:noreply, assign(socket, selected_role_ids: selected_ids)}
  end
end
