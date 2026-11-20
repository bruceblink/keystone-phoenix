defmodule KeystonePhoenixWeb.Live.AdminEvents.Organization do
  @moduledoc "LiveView event handlers for the organization domain."
  import Phoenix.Component, only: [assign: 2]
  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Post
  alias KeystonePhoenix.Role
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationExport
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationPosts
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationMenu
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleEditor
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleBulk
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationRolePagination
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleReload
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleRefresh
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleSelection
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleUsers
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationRolePermissions
  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationDepartmentRefresh
  alias KeystonePhoenixWeb.Live.AdminPages.OrganizationFilters
  alias KeystonePhoenixWeb.Live.AdminPages.FilterNavigation
  alias KeystonePhoenixWeb.Live.AdminPages.Reload
  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def handle_event("refresh-depts", params, socket) do
    if Support.panel_allowed?(socket, "depts") do
      {:noreply, OrganizationDepartmentRefresh.refresh(socket, params)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-dept", _params, socket) do
    if Support.permission_socket?(socket, "department:create") do
      {:noreply,
       assign(socket,
         dept_form: Support.empty_dept_form(),
         dept_feedback: nil,
         active_modal: "dept"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-dept", %{"dept-id" => dept_id}, socket) do
    if Support.permission_socket?(socket, "department:update") do
      case Enum.find(socket.assigns.dept_rows, &(to_string(&1["deptId"]) == dept_id)) do
        nil ->
          {:noreply,
           assign(socket, dept_feedback: Feedback.error(:resource_not_found, "找不到指定部门"))}

        dept ->
          {:noreply,
           assign(socket,
             dept_form: Map.merge(Support.empty_dept_form(), dept),
             dept_feedback: nil,
             active_modal: "dept"
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-dept", params, socket) do
    if Support.permission_socket?(socket, "department:create") or
         Support.permission_socket?(socket, "department:update") do
      dept_id = String.trim(params["deptId"] || "")

      result =
        if dept_id == "",
          do: Department.create_dept(params, authorization(socket, "department:create")),
          else:
            Department.update_dept(dept_id, params, authorization(socket, "department:update"))

      case result do
        {:ok, _dept} ->
          {:noreply,
           after_write(
             socket,
             :depts,
             if(dept_id == "", do: "部门已创建", else: "部门已更新"),
             "部门已保存，但列表刷新失败，请重试",
             dept_form: Support.empty_dept_form(),
             active_modal: nil
           )}

        error ->
          {:noreply, assign(socket, dept_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-dept-status", %{"dept-id" => dept_id, "status" => status}, socket) do
    if Support.permission_socket?(socket, "department:update") do
      case Department.update_dept(
             dept_id,
             %{"status" => status},
             authorization(socket, "department:update")
           ) do
        {:ok, _dept} ->
          {:noreply, after_write(socket, :depts, "部门状态已更新", "部门状态已更新，但列表刷新失败，请重试")}

        error ->
          {:noreply, assign(socket, dept_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-dept", %{"dept-id" => dept_id}, socket) do
    if Support.permission_socket?(socket, "department:delete") do
      case Department.delete_dept(dept_id, authorization(socket, "department:delete")) do
        :ok ->
          {:noreply,
           after_write(socket, :depts, "部门已删除", "部门已删除，但列表刷新失败，请重试",
             dept_form: Support.empty_dept_form(),
             active_modal: nil
           )}

        error ->
          {:noreply, assign(socket, dept_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-posts", params, socket) do
    if Support.panel_allowed?(socket, "posts") do
      filter =
        OrganizationFilters.organization_filter(params, socket.assigns[:post_filter], [
          "postKeyword",
          "postStatus"
        ])

      socket =
        assign(socket,
          post_filter: filter,
          post_form: Support.empty_post_form(),
          active_modal: nil
        )

      {:noreply, refresh_posts_page(socket, 1)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("paginate-posts", %{"page" => page}, socket) do
    case Integer.parse(to_string(page)) do
      {page_number, ""} when page_number > 0 ->
        {:noreply, refresh_posts_page(socket, page_number)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("export-posts", params, socket),
    do: OrganizationExport.handle_event("export-posts", params, socket)

  def handle_event("new-post", _params, socket) do
    if Support.permission_socket?(socket, "post:create") do
      {:noreply,
       assign(socket,
         post_form: Support.empty_post_form(),
         post_feedback: nil,
         active_modal: "post"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-post", %{"post-id" => post_id}, socket) do
    if Support.permission_socket?(socket, "post:update") do
      case Enum.find(socket.assigns.post_rows, &(to_string(&1["postId"]) == post_id)) do
        nil ->
          {:noreply,
           assign(socket, post_feedback: Feedback.error(:resource_not_found, "找不到指定岗位"))}

        post ->
          {:noreply,
           assign(socket,
             post_form: Map.merge(Support.empty_post_form(), post),
             post_feedback: nil,
             active_modal: "post"
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-post", params, socket) do
    if Support.permission_socket?(socket, "post:create") or
         Support.permission_socket?(socket, "post:update") do
      post_id = String.trim(params["postId"] || "")

      result =
        if post_id == "",
          do: Post.create_post(params, authorization(socket, "post:create")),
          else: Post.update_post(post_id, params, authorization(socket, "post:update"))

      case result do
        {:ok, _post} ->
          {:noreply,
           after_post_write(
             socket,
             if(post_id == "", do: "岗位已创建", else: "岗位已更新"),
             post_form: Support.empty_post_form(),
             active_modal: nil
           )}

        error ->
          {:noreply, assign(socket, post_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-post-status", %{"post-id" => post_id, "status" => status}, socket) do
    if Support.permission_socket?(socket, "post:update") do
      case Post.update_post(
             post_id,
             %{"status" => status},
             authorization(socket, "post:update")
           ) do
        {:ok, _post} ->
          {:noreply, after_post_write(socket, "岗位状态已更新")}

        error ->
          {:noreply, assign(socket, post_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-post", %{"post-id" => post_id}, socket) do
    if Support.permission_socket?(socket, "post:delete") do
      case Post.delete_posts([post_id], authorization(socket, "post:delete")) do
        :ok ->
          {:noreply,
           after_post_write(socket, "岗位已删除",
             post_form: Support.empty_post_form(),
             active_modal: nil
           )}

        error ->
          {:noreply, assign(socket, post_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-roles", params, socket) do
    if Support.panel_allowed?(socket, "roles") do
      {:noreply, OrganizationRoleRefresh.refresh(socket, params)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("paginate-roles", %{"page" => page}, socket) do
    case Integer.parse(to_string(page)) do
      {page_number, ""} when page_number > 0 ->
        {:noreply, OrganizationRolePagination.refresh(socket, page_number)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("export-roles", params, socket),
    do: OrganizationExport.handle_event("export-roles", params, socket)

  def handle_event(event, params, socket) when event in ["new-role", "edit-role", "save-role"],
    do: OrganizationRoleEditor.handle_event(event, params, socket)

  def handle_event(event, params, socket)
      when event in [
             "filter-role-permissions",
             "toggle-role-permission",
             "open-role-permissions",
             "save-role-permissions"
           ],
      do: OrganizationRolePermissions.handle_event(event, params, socket)

  def handle_event("toggle-role-selection", params, socket),
    do: OrganizationRoleSelection.handle_event("toggle-role-selection", params, socket)

  def handle_event("toggle-all-role-selection", params, socket),
    do: OrganizationRoleSelection.handle_event("toggle-all-role-selection", params, socket)

  def handle_event("toggle-role-status", %{"role-id" => role_id, "status" => status}, socket) do
    if Support.permission_socket?(socket, "role:update") do
      case Role.change_status(role_id, status, authorization(socket, "role:update")) do
        {:ok, _role} ->
          socket =
            after_write(socket, :roles, "角色状态已更新", "角色状态已更新，但列表刷新失败，请重试", selected_role_ids: [])

          {:noreply, OrganizationRoleSelection.clear_role_selection(socket)}

        error ->
          {:noreply, assign(socket, role_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("open-role-delete", _params, socket),
    do: OrganizationRoleBulk.open_confirmation(socket)

  def handle_event("delete-role", %{"role-id" => role_id}, socket),
    do: OrganizationRoleBulk.delete_roles(socket, [role_id])

  def handle_event("delete-role", %{"role-ids" => role_ids}, socket) do
    OrganizationRoleBulk.delete_roles(
      socket,
      List.wrap(role_ids) |> Enum.flat_map(&String.split(to_string(&1), ","))
    )
  end

  def handle_event("select-role", %{"role-id" => role_id}, socket) do
    if Support.permission_socket?(socket, "role:read") do
      case Enum.find(socket.assigns.role_rows, &(to_string(&1["roleId"]) == role_id)) do
        nil ->
          {:noreply,
           assign(socket,
             role_user_feedback: Feedback.error(:resource_not_found, "找不到指定角色")
           )}

        role ->
          case AdminReadSupport.role_users(
                 role_id,
                 socket.assigns.current_user,
                 socket.assigns.page_sizes["role-users-allocated"]
               ) do
            {:ok, users} ->
              {:noreply,
               assign(socket,
                 selected_role_id: role_id,
                 selected_role_name: role["roleName"],
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
                 role_user_feedback: nil
               )}

            {:error, reason} ->
              {:noreply,
               OrganizationRoleSelection.role_users_failed(
                 socket,
                 role_id,
                 role["roleName"],
                 reason
               )}
          end
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("close-role-users", _params, socket),
    do: {:noreply, OrganizationRoleSelection.clear_role_selection(socket)}

  def handle_event(event, params, socket)
      when event in ["assign-role-user", "unassign-role-user"],
      do: OrganizationRoleUsers.handle_event(event, params, socket)

  def handle_event("refresh-menus", params, socket) do
    if Support.panel_allowed?(socket, "menus") do
      filter = OrganizationFilters.menu_filter(params, socket.assigns[:menu_filter])

      socket =
        refresh_rows(socket, :menus, "菜单列表刷新失败，请重试",
          menu_form: Support.empty_menu_form(),
          menu_filter: filter,
          menu_role_codes: [],
          active_modal: nil
        )

      {:noreply, Phoenix.LiveView.push_patch(socket, to: FilterNavigation.path("menus", filter))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-menu", _params, socket) do
    if Support.permission_socket?(socket, "menu:create") do
      {:noreply,
       assign(socket,
         menu_form: Support.empty_menu_form(),
         menu_feedback: nil,
         menu_role_codes: [],
         active_modal: "menu"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-menu", params, socket), do: OrganizationMenu.edit(params, socket)

  def handle_event("save-menu", params, socket), do: OrganizationMenu.save(params, socket)

  def handle_event("toggle-menu-status", %{"menu-id" => menu_id, "status" => status}, socket) do
    if Support.permission_socket?(socket, "menu:update") do
      case Menu.update_menu(
             menu_id,
             %{"status" => status},
             authorization(socket, "menu:update")
           ) do
        {:ok, _menu} ->
          {:noreply, after_write(socket, :menus, "菜单状态已更新", "菜单状态已更新，但列表刷新失败，请重试")}

        error ->
          {:noreply, assign(socket, menu_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-menu", %{"menu-id" => menu_id}, socket) do
    if Support.permission_socket?(socket, "menu:delete") do
      case Menu.delete_menu(menu_id, authorization(socket, "menu:delete")) do
        :ok ->
          {:noreply,
           after_write(socket, :menus, "菜单已删除", "菜单已删除，但列表刷新失败，请重试",
             menu_form: Support.empty_menu_form(),
             menu_role_codes: [],
             active_modal: nil
           )}

        error ->
          {:noreply, assign(socket, menu_feedback: Support.form_error(error))}
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

  defp refresh_rows(socket, resource, message, extra) do
    {loader, rows_key, feedback_key} = resource_loader(resource)
    Reload.refresh(socket, loader, rows_key, feedback_key, message, extra)
  end

  defp refresh_posts_page(socket, page) do
    OrganizationPosts.refresh(socket, page)
  end

  defp after_post_write(socket, success, extra \\ []),
    do: OrganizationPosts.after_success(socket, success, extra)

  defp after_write(socket, resource, success, message, extra \\ []) do
    if resource == :roles do
      OrganizationRoleReload.after_success(socket, success, message, extra)
    else
      {loader, rows_key, feedback_key} = resource_loader(resource)
      Reload.after_success(socket, loader, rows_key, feedback_key, success, message, extra)
    end
  end

  defp resource_loader(:depts), do: {&AdminReadSupport.departments/1, :dept_rows, :dept_feedback}
  defp resource_loader(:posts), do: {&AdminReadSupport.posts/1, :post_rows, :post_feedback}
  defp resource_loader(:menus), do: {&AdminReadSupport.menus/1, :menu_rows, :menu_feedback}
end
