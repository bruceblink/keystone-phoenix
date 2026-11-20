defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleUsers do
  @moduledoc "角色页面的用户分配事件。"

  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias KeystonePhoenix.Role
  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def handle_event("assign-role-user", %{"user-id" => user_id}, socket),
    do: assign_user(socket, user_id)

  def handle_event("unassign-role-user", %{"user-id" => user_id}, socket),
    do: unassign_user(socket, user_id)

  def assign_user(socket, user_id) do
    update(socket, fn role_id ->
      Role.assign_users(role_id, [user_id], authorization(socket, "role:assign"))
    end)
  end

  def unassign_user(socket, user_id) do
    update(socket, fn role_id ->
      Role.unassign_users(role_id, [user_id], authorization(socket, "role:assign"))
    end)
  end

  @doc "按当前角色读取指定栏的页面；失败时保留原页和数据。"
  def paginate(socket, panel, page) do
    role_id = socket.assigns.selected_role_id
    size = socket.assigns.page_sizes[panel]

    if role_id != "" and Support.permission_socket?(socket, "role:read") do
      case AdminReadSupport.role_users_page(
             role_id,
             socket.assigns.current_user,
             panel,
             page,
             size
           ) do
        {:ok, actual_page, result} ->
          {rows_key, total_key} =
            if panel == "role-users-allocated",
              do: {:allocated_role_user_rows, :allocated},
              else: {:unallocated_role_user_rows, :unallocated}

          {:noreply,
           socket
           |> assign(rows_key, result.rows)
           |> assign(
             role_user_totals: Map.put(socket.assigns.role_user_totals, total_key, result.total),
             page_nums: Map.put(socket.assigns.page_nums, panel, actual_page),
             role_user_feedback: nil
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket, role_user_feedback: Support.read_error_feedback(reason, "角色成员读取失败，请重试"))}
      end
    else
      {:noreply, socket}
    end
  end

  defp update(socket, operation) do
    if Support.permission_socket?(socket, "role:assign") and
         socket.assigns.selected_role_id != "" do
      role_id = socket.assigns.selected_role_id

      case operation.(role_id) do
        :ok ->
          reload_members(socket, role_id)

        error ->
          {:noreply, assign(socket, role_user_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  defp reload_members(socket, role_id) do
    case AdminReadSupport.role_users(
           role_id,
           socket.assigns.current_user,
           socket.assigns.page_sizes["role-users-allocated"]
         ) do
      {:ok, users} ->
        {:noreply,
         assign(socket,
           page_nums:
             socket.assigns.page_nums
             |> Map.put("role-users-allocated", 1)
             |> Map.put("role-users-unallocated", 1),
           allocated_role_user_rows: users.allocated.rows,
           unallocated_role_user_rows: users.unallocated.rows,
           role_user_totals: %{
             allocated: users.allocated.total,
             unallocated: users.unallocated.total
           },
           role_user_feedback: "角色用户已更新"
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           role_user_feedback: Support.read_error_feedback(reason, "角色用户已更新，但列表刷新失败，请重试")
         )}
    end
  end

  defp authorization(socket, permission) do
    principal =
      socket.assigns.current_user
      |> Map.put(:permissions, List.wrap(socket.assigns[:permissions]))

    [authorization: %{principal: principal, permission: permission}]
  end
end
