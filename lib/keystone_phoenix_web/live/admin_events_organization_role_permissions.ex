defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationRolePermissions do
  @moduledoc "角色权限目录筛选和逐项选择事件。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Authz.PermissionCatalog
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Role.Permissions
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleReload
  alias KeystonePhoenixWeb.Live.AdminPages.Organization
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  # 只在角色元数据表单或独立权限表单中更新目录筛选条件。
  def handle_event("filter-role-permissions", %{"permissionQuery" => query}, socket) do
    if editable_modal?(socket) and Support.permission_socket?(socket, "role:manage") do
      {:noreply, assign(socket, role_permission_query: String.trim(to_string(query)))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("filter-role-permissions", _params, socket),
    do: handle_event("filter-role-permissions", %{"permissionQuery" => ""}, socket)

  # 权限编辑与基础角色编辑分开，避免要求 role:update。
  def handle_event("open-role-permissions", %{"role-id" => role_id}, socket) do
    if Support.permission_socket?(socket, "role:read") and
         Support.permission_socket?(socket, "role:manage") do
      open_permissions(socket, role_id)
    else
      {:noreply, socket}
    end
  end

  def handle_event("open-role-permissions", _params, socket), do: {:noreply, socket}

  # 保存时只读取已打开表单的角色 ID 和服务端状态，不信任提交参数中的目标 ID。
  def handle_event("save-role-permissions", _params, socket) do
    form = socket.assigns[:role_permissions_form] || %{}

    if Support.permission_socket?(socket, "role:manage") and
         socket.assigns[:active_modal] == "role-permissions" and form["loaded"] == true do
      save_permissions(socket, form)
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "toggle-role-permission",
        %{"permission" => permission, "selected" => selected},
        socket
      ) do
    form_key = permission_form_key(socket)
    form = get_in(socket.assigns, [form_key]) || %{}

    if (form_key && Support.permission_socket?(socket, "role:manage")) and
         form_loaded?(socket, form) and grantable_permission?(socket, permission) do
      permissions = selected_permissions(form)

      permissions =
        if selected in ["true", "1"],
          do: Enum.uniq([permission | permissions]),
          else: List.delete(permissions, permission)

      {:noreply,
       assign(socket, %{form_key => Map.put(form, "permissions", Enum.join(permissions, ","))})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-role-permission", _params, socket), do: {:noreply, socket}

  defp open_permissions(socket, role_id) do
    role = Enum.find(socket.assigns.role_rows, &(to_string(&1["roleId"]) == role_id))

    with true <- not is_nil(role),
         authorization <- Support.authorization_options(socket, "role:read"),
         {:ok, _record} <- Role.get_role(role_id, authorization),
         {:ok, permissions} <- Permissions.list_for_role(role_id, authorization) do
      {:noreply,
       assign(socket,
         active_modal: "role-permissions",
         role_permission_query: "",
         role_permissions_feedback: nil,
         role_permissions_form: %{
           "roleId" => role_id,
           "roleName" => role["roleName"],
           "permissions" => Enum.join(permissions, ","),
           "loaded" => true
         }
       )}
    else
      nil -> open_permissions_failed(socket, role_id, :not_found)
      false -> open_permissions_failed(socket, role_id, :not_found)
      {:error, reason} -> open_permissions_failed(socket, role_id, reason)
    end
  end

  defp open_permissions_failed(socket, role_id, reason) do
    role_name =
      Enum.find_value(socket.assigns.role_rows, "", fn role ->
        if to_string(role["roleId"]) == role_id, do: role["roleName"]
      end)

    {:noreply,
     assign(socket,
       active_modal: "role-permissions",
       role_permission_query: "",
       role_permissions_feedback: Support.read_error_feedback(reason, "角色权限读取失败，请重试"),
       role_permissions_form: %{
         "roleId" => role_id,
         "roleName" => role_name,
         "permissions" => "",
         "loaded" => false
       }
     )}
  end

  defp save_permissions(socket, form) do
    role_id = form["roleId"]
    options = Support.authorization_options(socket, "role:manage") ++ [permission: "role:manage"]
    attrs = %{"permissions" => form["permissions"] || ""}

    case Role.update_role(role_id, attrs, options) do
      {:ok, _role} ->
        socket =
          OrganizationRoleReload.after_success(
            socket,
            "角色权限已更新",
            "角色权限已保存，但列表刷新失败，请重试",
            active_modal: nil,
            role_permissions_form: empty_form(),
            role_permissions_feedback: nil
          )

        {:noreply, socket}

      error ->
        {:noreply,
         assign(socket,
           role_permissions_feedback: Support.form_error(error)
         )}
    end
  end

  defp editable_modal?(socket),
    do: socket.assigns[:active_modal] in ["role", "role-permissions"]

  defp permission_form_key(%{assigns: %{active_modal: "role-permissions"}}),
    do: :role_permissions_form

  defp permission_form_key(%{assigns: %{active_modal: "role"}}), do: :role_form
  defp permission_form_key(_socket), do: nil

  defp form_loaded?(%{assigns: %{active_modal: "role-permissions"}}, form),
    do: form["loaded"] == true

  defp form_loaded?(%{assigns: %{active_modal: "role"}}, _form), do: true
  defp form_loaded?(_socket, _form), do: false

  # 页面权限目录就是当前主体可授予的集合，伪造事件不能加入隐藏权限。
  defp grantable_permission?(socket, permission) do
    PermissionCatalog.registered?(permission) and
      Enum.any?(
        Organization.role_permission_entries(socket.assigns[:permissions]),
        &(&1.permission == permission)
      )
  end

  defp empty_form,
    do: %{"roleId" => "", "roleName" => "", "permissions" => "", "loaded" => false}

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
