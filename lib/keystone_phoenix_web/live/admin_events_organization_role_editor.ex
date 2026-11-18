defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleEditor do
  @moduledoc "角色基础资料的读取、创建和修改事件。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Role.Permissions
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationMenuParams
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleReload
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleSelection
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  # 新建角色只允许具有 role:create 的当前会话打开。
  def handle_event("new-role", _params, socket) do
    if Support.permission_socket?(socket, "role:create") do
      {:noreply,
       assign(socket,
         role_form: Support.empty_role_form(),
         role_permission_query: "",
         role_feedback: nil,
         active_modal: "role"
       )}
    else
      {:noreply, socket}
    end
  end

  # 无 role:manage 时只加载基础资料，不读取或提交菜单、权限和数据范围字段。
  def handle_event("edit-role", %{"role-id" => role_id}, socket) do
    if Support.permission_socket?(socket, "role:update") do
      case Enum.find(socket.assigns.role_rows, &(to_string(&1["roleId"]) == role_id)) do
        nil ->
          {:noreply,
           assign(socket, role_feedback: Feedback.error(:resource_not_found, "找不到指定角色"))}

        role ->
          load_role_form(socket, role_id, role)
      end
    else
      {:noreply, socket}
    end
  end

  # 根据当前记录选择 create 或 update，并过滤调用者无权管理的元数据字段。
  def handle_event("save-role", params, socket) do
    role_id = String.trim(params["roleId"] || "")
    command = if role_id == "", do: "role:create", else: "role:update"

    if Support.permission_socket?(socket, command) do
      save_role(socket, params, role_id)
    else
      {:noreply, socket}
    end
  end

  defp load_role_form(socket, role_id, role) do
    form = Support.empty_role_form() |> Map.merge(role)

    if Support.permission_socket?(socket, "role:manage") do
      authorization = Support.authorization_options(socket, "role:read")

      with {:ok, menu_ids} <- Role.menu_ids_for_role(role_id, authorization),
           {:ok, permissions} <- Permissions.list_for_role(role_id, authorization) do
        form =
          form
          |> Map.put("menuIds", Enum.join(menu_ids, ","))
          |> Map.put("permissions", Enum.join(permissions, ","))

        {:noreply, assign_role_form(socket, form)}
      else
        {:error, reason} ->
          {:noreply,
           assign(socket,
             role_feedback: Support.read_error_feedback(reason, "角色权限读取失败，请重试")
           )}
      end
    else
      {:noreply, assign_role_form(socket, form)}
    end
  end

  defp assign_role_form(socket, form) do
    assign(socket,
      role_form: form,
      role_permission_query: "",
      role_feedback: nil,
      active_modal: "role"
    )
  end

  defp save_role(socket, params, role_id) do
    params = role_attrs(params, Support.permission_socket?(socket, "role:manage"))

    if Authz.role_metadata_allowed?(socket.assigns.current_user, params) do
      result =
        if role_id == "",
          do: Role.create_role(params, authorization(socket, "role:create")),
          else: Role.update_role(role_id, params, authorization(socket, "role:update"))

      case result do
        {:ok, _role} ->
          socket =
            OrganizationRoleReload.after_success(
              socket,
              if(role_id == "", do: "角色已创建", else: "角色已更新"),
              "角色已保存，但列表刷新失败，请重试",
              role_form: Support.empty_role_form(),
              active_modal: nil
            )

          {:noreply, OrganizationRoleSelection.clear_role_selection(socket)}

        error ->
          {:noreply, assign(socket, role_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  # 角色元数据只在 role:manage 页面表单中提交；其他调用仅保留基础资料。
  defp role_attrs(params, true) do
    params
    |> Map.drop(["permissionQuery"])
    |> OrganizationMenuParams.normalize_role_menu_ids()
    |> trim_permissions()
  end

  defp role_attrs(params, false) do
    Map.take(params, ["roleId", "roleName", "roleKey", "roleSort", "status", "remark"])
  end

  # 缺少权限字段时保持服务层的“不修改”语义，避免意外清空已有绑定。
  defp trim_permissions(params) do
    case Map.fetch(params, "permissions") do
      {:ok, permissions} when is_binary(permissions) ->
        Map.put(params, "permissions", String.trim(permissions))

      _ ->
        params
    end
  end

  defp authorization(socket, permission) do
    principal =
      socket.assigns.current_user
      |> Map.put(:permissions, List.wrap(socket.assigns[:permissions]))

    [authorization: %{principal: principal, permission: permission}]
  end
end
