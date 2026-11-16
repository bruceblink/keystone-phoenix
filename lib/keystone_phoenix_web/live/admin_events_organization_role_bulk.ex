defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleBulk do
  @moduledoc "角色页面的批量删除事件。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Role
  alias KeystonePhoenixWeb.Live.AdminPages.Reload
  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def delete_roles(socket, role_ids) do
    if Support.permission_socket?(socket, "role:delete") do
      role_ids = Enum.filter(role_ids, &(String.trim(&1) != ""))

      case Role.delete_roles(role_ids, authorization(socket, "role:delete")) do
        {:ok, _} ->
          {:noreply,
           Reload.after_success(
             socket,
             &AdminReadSupport.roles/1,
             :role_rows,
             :role_feedback,
             "已删除 #{length(role_ids)} 个角色",
             "角色已删除，但列表刷新失败，请重试",
             selected_role_ids: [],
             role_form: Support.empty_role_form(),
             active_modal: nil,
             selected_role_id: "",
             selected_role_name: "",
             allocated_role_user_rows: [],
             unallocated_role_user_rows: [],
             role_user_feedback: nil
           )}

        error ->
          {:noreply, assign(socket, role_feedback: Support.form_error(error))}
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
