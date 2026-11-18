defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationMenu do
  @moduledoc "LiveView 菜单编辑和菜单角色绑定事件。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Menu.RoleAssignment
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminPages.Reload
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationMenuParams
  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def edit(%{"menu-id" => menu_id}, socket) do
    if Support.permission_socket?(socket, "menu:update") do
      case Enum.find(socket.assigns.menu_rows, &(to_string(&1["menuId"] || &1["id"]) == menu_id)) do
        nil ->
          {:noreply,
           assign(socket, menu_feedback: Feedback.error(:resource_not_found, "找不到指定菜单"))}

        menu ->
          form = menu_form(menu)

          case load_role_codes(menu_id, socket) do
            {:ok, role_codes} ->
              {:noreply,
               assign(socket,
                 menu_form: form,
                 menu_role_codes: role_codes,
                 menu_feedback: nil,
                 active_modal: "menu"
               )}

            {:error, reason} ->
              {:noreply, assign(socket, menu_feedback: Support.form_error({:error, reason}))}
          end
      end
    else
      {:noreply, socket}
    end
  end

  def save(params, socket) do
    allowed? =
      Support.permission_socket?(socket, "menu:create") or
        Support.permission_socket?(socket, "menu:update")

    if allowed? and Authz.menu_metadata_allowed?(socket.assigns.current_user, params) do
      params = OrganizationMenuParams.normalize_menu_params(params, socket.assigns[:menu_form])
      menu_id = String.trim(params["menuId"] || "")

      result =
        if menu_id == "",
          do: Menu.create_menu(params, authorization(socket, "menu:create")),
          else: Menu.update_menu(menu_id, params, authorization(socket, "menu:update"))

      case result do
        {:ok, menu} -> save_roles(menu, params, menu_id, socket)
        error -> {:noreply, assign(socket, menu_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  defp save_roles(menu, params, previous_id, socket) do
    menu_id = menu_id(menu, previous_id)
    role_codes = role_codes(params)

    case replace_role_codes(menu_id, role_codes, socket) do
      :ok ->
        {:noreply,
         Reload.after_success(
           socket,
           &AdminReadSupport.menus/1,
           :menu_rows,
           :menu_feedback,
           if(previous_id == "", do: "菜单已创建", else: "菜单已更新"),
           "菜单已保存，但列表刷新失败，请重试",
           menu_form: Support.empty_menu_form(),
           menu_role_codes: [],
           active_modal: nil
         )}

      {:error, reason} ->
        # 菜单本体已保存；保留其 ID 和字段，让用户修正角色后更新同一条菜单。
        {:noreply,
         assign(socket,
           menu_form: menu |> Menu.menu_to_map() |> menu_form(),
           menu_role_codes: role_codes,
           active_modal: "menu",
           menu_feedback: role_assignment_error(reason)
         )}
    end
  end

  defp load_role_codes(menu_id, socket) do
    if Support.permission_socket?(socket, "menu:manage"),
      do: RoleAssignment.list(menu_id, authorization(socket, "menu:manage")),
      else: {:ok, []}
  end

  defp replace_role_codes(menu_id, role_codes, socket) do
    if Support.permission_socket?(socket, "menu:manage") do
      RoleAssignment.replace(menu_id, role_codes, authorization(socket, "menu:manage"))
    else
      :ok
    end
  end

  # 角色可能在表单打开后停用或删除，提示用户重新选择仍可用的角色。
  defp role_assignment_error(:role_not_found),
    do: Feedback.error(:resource_not_found, "所选角色不存在或已停用，请重新选择后重试")

  defp role_assignment_error(reason), do: Support.form_error({:error, reason})

  defp menu_form(menu) do
    enabled = Map.get(menu, "enabled", menu["status"] in [1, "1", true])

    Support.empty_menu_form()
    |> Map.merge(menu)
    |> Map.put("id", menu["id"] || menu["menuId"])
    |> Map.put("code", menu["code"] || menu["menuCode"] || menu["menuId"])
    |> Map.put("name", menu["name"] || menu["menuName"])
    |> Map.put("component", menu["component"] || menu["routerName"] || "")
    |> Map.put("sortOrder", menu["sortOrder"] || menu["rank"] || 0)
    |> Map.put("enabled", enabled in [true, 1, "true", "1"])
    |> Map.put("metaInfo", Jason.encode!(menu["meta"] || %{}))
    |> Map.put("isButton", if(menu["isButton"], do: "true", else: "false"))
  end

  defp menu_id(%{menu_id: menu_id}, _fallback), do: menu_id
  defp menu_id(%{"menuId" => menu_id}, _fallback), do: menu_id
  defp menu_id(_menu, fallback), do: fallback

  defp role_codes(params) do
    params
    |> Map.get("menuRoleCodes[]", Map.get(params, "menuRoleCodes", []))
    |> List.wrap()
    |> List.flatten()
    |> Enum.map(&String.trim(to_string(&1)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp authorization(socket, permission) do
    principal =
      socket.assigns.current_user
      |> Map.put(:permissions, List.wrap(socket.assigns[:permissions]))

    [authorization: %{principal: principal, permission: permission}]
  end
end
