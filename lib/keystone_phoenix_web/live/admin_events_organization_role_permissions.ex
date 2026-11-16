defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationRolePermissions do
  @moduledoc "角色权限目录筛选和逐项选择事件。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Authz.PermissionCatalog
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def handle_event("filter-role-permissions", %{"permissionQuery" => query}, socket),
    do: {:noreply, assign(socket, role_permission_query: String.trim(to_string(query)))}

  def handle_event("filter-role-permissions", _params, socket),
    do: {:noreply, assign(socket, role_permission_query: "")}

  def handle_event(
        "toggle-role-permission",
        %{"permission" => permission, "selected" => selected},
        socket
      ) do
    if Support.permission_socket?(socket, "role:manage") and
         PermissionCatalog.registered?(permission) do
      permissions = selected_permissions(socket.assigns[:role_form])

      permissions =
        if selected in ["true", "1"],
          do: Enum.uniq([permission | permissions]),
          else: List.delete(permissions, permission)

      {:noreply,
       assign(socket,
         role_form: Map.put(socket.assigns.role_form, "permissions", Enum.join(permissions, ","))
       )}
    else
      {:noreply, socket}
    end
  end

  defp selected_permissions(form) do
    form
    |> Map.get("permissions", "")
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end
end
