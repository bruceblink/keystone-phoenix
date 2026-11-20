defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleSelection do
  @moduledoc "角色列表的当前结果集选择事件。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminSupport
  alias KeystonePhoenixWeb.Live.AdminPages.OrganizationFilters

  @doc "角色切换读取失败时清理其他角色的数据；重试当前角色失败时保留已显示的数据。"
  def role_users_failed(socket, role_id, role_name, reason) do
    socket =
      if socket.assigns.selected_role_id == role_id do
        socket
      else
        assign(socket,
          allocated_role_user_rows: [],
          unallocated_role_user_rows: [],
          role_user_totals: %{allocated: 0, unallocated: 0},
          page_nums: reset_member_pages(socket.assigns.page_nums)
        )
      end

    assign(socket,
      selected_role_id: role_id,
      selected_role_name: role_name,
      role_user_feedback: AdminSupport.read_error_feedback(reason, "角色成员读取失败，请重试")
    )
  end

  @doc "关闭角色成员面板并重置当前成员分页，避免旧选择残留。"
  def clear_role_selection(socket) do
    assign(socket,
      selected_role_ids: [],
      selected_role_id: "",
      selected_role_name: "",
      allocated_role_user_rows: [],
      unallocated_role_user_rows: [],
      role_user_totals: %{allocated: 0, unallocated: 0},
      role_user_feedback: nil,
      page_nums: reset_member_pages(socket.assigns.page_nums)
    )
  end

  defp reset_member_pages(page_nums) do
    page_nums
    |> Map.put("role-users-allocated", 1)
    |> Map.put("role-users-unallocated", 1)
  end

  def handle_event(
        "toggle-role-selection",
        %{"role-id" => role_id, "selected" => selected},
        socket
      ) do
    if AdminSupport.permission_socket?(socket, "role:delete") do
      selected_ids = Map.get(socket.assigns, :selected_role_ids, [])

      selected_ids =
        if selected == "true",
          do: Enum.uniq([role_id | selected_ids]),
          else: List.delete(selected_ids, role_id)

      {:noreply, assign(socket, selected_role_ids: selected_ids)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-all-role-selection", %{"selected" => selected}, socket) do
    if AdminSupport.permission_socket?(socket, "role:delete") do
      role_ids =
        Map.get(socket.assigns, :role_page_rows, socket.assigns.role_rows)
        |> OrganizationFilters.filtered_roles(socket.assigns[:role_filter])
        |> Enum.map(&to_string(&1["roleId"]))

      selected_ids = Map.get(socket.assigns, :selected_role_ids, [])

      selected_ids =
        if selected == "true",
          do: Enum.uniq(selected_ids ++ role_ids),
          else: selected_ids -- role_ids

      {:noreply, assign(socket, selected_role_ids: selected_ids)}
    else
      {:noreply, socket}
    end
  end

  # 不完整的伪造选择事件保持当前状态，不触发 LiveView 函数错误。
  def handle_event(event, _params, socket)
      when event in ["toggle-role-selection", "toggle-all-role-selection"],
      do: {:noreply, socket}
end
