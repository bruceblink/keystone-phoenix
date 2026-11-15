defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleUsers do
  @moduledoc "角色页面的用户分配事件。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Role
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def assign_user(socket, user_id) do
    update(socket, fn role_id ->
      Role.assign_users(role_id, [user_id], authorization(socket, "role:assign"))
    end)
  end

  def unassign_user(socket, user_id) do
    update(socket, fn _role_id ->
      Role.unassign_users([user_id], authorization(socket, "role:assign"))
    end)
  end

  defp update(socket, operation) do
    if Support.permission_socket?(socket, "role:assign") and
         socket.assigns.selected_role_id != "" do
      role_id = socket.assigns.selected_role_id

      case operation.(role_id) do
        :ok ->
          {:noreply,
           assign(socket,
             role_rows: Support.load_roles_for_socket(socket),
             role_feedback: "角色用户已更新",
             selected_role_id: "",
             selected_role_name: "",
             allocated_role_user_rows: [],
             unallocated_role_user_rows: [],
             role_user_feedback: nil
           )}

        error ->
          {:noreply, assign(socket, role_user_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  defp authorization(socket, permission) do
    principal =
      socket.assigns.current_user
      |> Map.put(:permissions, List.wrap(socket.assigns[:permissions]))

    [authorization: %{principal: principal, permission: permission}]
  end
end
