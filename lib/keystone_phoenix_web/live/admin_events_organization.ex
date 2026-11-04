defmodule KeystonePhoenixWeb.Live.AdminEvents.Organization do
  @moduledoc "LiveView event handlers for the organization domain."

  import Phoenix.Component, only: [assign: 2]
  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Post
  alias KeystonePhoenix.Role
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def handle_event("refresh-depts", _params, socket) do
    if Support.admin_socket?(socket) do
      {:noreply,
       assign(socket,
         dept_rows: Support.load_depts(),
         dept_form: Support.empty_dept_form(),
         dept_feedback: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-dept", _params, socket) do
    if Support.admin_socket?(socket) do
      {:noreply, assign(socket, dept_form: Support.empty_dept_form(), dept_feedback: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-dept", %{"dept-id" => dept_id}, socket) do
    if Support.admin_socket?(socket) do
      case Enum.find(socket.assigns.dept_rows, &(to_string(&1["deptId"]) == dept_id)) do
        nil ->
          {:noreply, assign(socket, dept_feedback: "找不到指定部门")}

        dept ->
          {:noreply,
           assign(socket,
             dept_form: Map.merge(Support.empty_dept_form(), dept),
             dept_feedback: nil
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-dept", params, socket) do
    if Support.admin_socket?(socket) do
      dept_id = String.trim(params["deptId"] || "")

      result =
        if dept_id == "",
          do: Department.create_dept(params),
          else: Department.update_dept(dept_id, params)

      case result do
        {:ok, _dept} ->
          {:noreply,
           assign(socket,
             dept_rows: Support.load_depts(),
             dept_form: Support.empty_dept_form(),
             dept_feedback: if(dept_id == "", do: "部门已创建", else: "部门已更新")
           )}

        error ->
          {:noreply, assign(socket, dept_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-dept-status", %{"dept-id" => dept_id, "status" => status}, socket) do
    if Support.admin_socket?(socket) do
      case Department.update_dept(dept_id, %{"status" => status}) do
        {:ok, _dept} ->
          {:noreply, assign(socket, dept_rows: Support.load_depts(), dept_feedback: "部门状态已更新")}

        error ->
          {:noreply, assign(socket, dept_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-dept", %{"dept-id" => dept_id}, socket) do
    if Support.admin_socket?(socket) do
      case Department.delete_dept(dept_id) do
        :ok ->
          {:noreply,
           assign(socket,
             dept_rows: Support.load_depts(),
             dept_form: Support.empty_dept_form(),
             dept_feedback: "部门已删除"
           )}

        error ->
          {:noreply, assign(socket, dept_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-posts", _params, socket) do
    if Support.admin_socket?(socket) do
      {:noreply,
       assign(socket,
         post_rows: Support.load_posts(),
         post_form: Support.empty_post_form(),
         post_feedback: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-post", _params, socket) do
    if Support.admin_socket?(socket) do
      {:noreply, assign(socket, post_form: Support.empty_post_form(), post_feedback: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-post", %{"post-id" => post_id}, socket) do
    if Support.admin_socket?(socket) do
      case Enum.find(socket.assigns.post_rows, &(to_string(&1["postId"]) == post_id)) do
        nil ->
          {:noreply, assign(socket, post_feedback: "找不到指定岗位")}

        post ->
          {:noreply,
           assign(socket,
             post_form: Map.merge(Support.empty_post_form(), post),
             post_feedback: nil
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-post", params, socket) do
    if Support.admin_socket?(socket) do
      post_id = String.trim(params["postId"] || "")

      result =
        if post_id == "", do: Post.create_post(params), else: Post.update_post(post_id, params)

      case result do
        {:ok, _post} ->
          {:noreply,
           assign(socket,
             post_rows: Support.load_posts(),
             post_form: Support.empty_post_form(),
             post_feedback: if(post_id == "", do: "岗位已创建", else: "岗位已更新")
           )}

        error ->
          {:noreply, assign(socket, post_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-post-status", %{"post-id" => post_id, "status" => status}, socket) do
    if Support.admin_socket?(socket) do
      case Post.update_post(post_id, %{"status" => status}) do
        {:ok, _post} ->
          {:noreply, assign(socket, post_rows: Support.load_posts(), post_feedback: "岗位状态已更新")}

        error ->
          {:noreply, assign(socket, post_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-post", %{"post-id" => post_id}, socket) do
    if Support.admin_socket?(socket) do
      case Post.delete_posts([post_id]) do
        :ok ->
          {:noreply,
           assign(socket,
             post_rows: Support.load_posts(),
             post_form: Support.empty_post_form(),
             post_feedback: "岗位已删除"
           )}

        error ->
          {:noreply, assign(socket, post_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-roles", _params, socket) do
    if Support.admin_socket?(socket) do
      {:noreply,
       assign(socket,
         role_rows: Support.load_roles(),
         role_form: Support.empty_role_form(),
         role_feedback: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-role", _params, socket) do
    if Support.admin_socket?(socket) do
      {:noreply, assign(socket, role_form: Support.empty_role_form(), role_feedback: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-role", %{"role-id" => role_id}, socket) do
    if Support.admin_socket?(socket) do
      case Enum.find(socket.assigns.role_rows, &(to_string(&1["roleId"]) == role_id)) do
        nil ->
          {:noreply, assign(socket, role_feedback: "找不到指定角色")}

        role ->
          menu_ids = Role.menu_ids_for_role(role_id) |> Enum.join(",")
          form = role |> Map.merge(Support.empty_role_form()) |> Map.put("menuIds", menu_ids)
          {:noreply, assign(socket, role_form: form, role_feedback: nil)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-role", params, socket) do
    if Support.admin_socket?(socket) do
      role_id = String.trim(params["roleId"] || "")
      params = Map.update(params, "menuIds", "", &String.trim/1)

      result =
        if role_id == "", do: Role.create_role(params), else: Role.update_role(role_id, params)

      case result do
        {:ok, _role} ->
          {:noreply,
           assign(socket,
             role_rows: Support.load_roles(),
             role_form: Support.empty_role_form(),
             role_feedback: if(role_id == "", do: "角色已创建", else: "角色已更新")
           )}

        error ->
          {:noreply, assign(socket, role_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-role-status", %{"role-id" => role_id, "status" => status}, socket) do
    if Support.admin_socket?(socket) do
      case Role.change_status(role_id, status) do
        {:ok, _role} ->
          {:noreply, assign(socket, role_rows: Support.load_roles(), role_feedback: "角色状态已更新")}

        error ->
          {:noreply, assign(socket, role_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-role", %{"role-id" => role_id}, socket) do
    if Support.admin_socket?(socket) do
      case Role.delete_role(role_id) do
        {:ok, _} ->
          {:noreply,
           assign(socket,
             role_rows: Support.load_roles(),
             role_form: Support.empty_role_form(),
             role_feedback: "角色已删除"
           )}

        :ok ->
          {:noreply,
           assign(socket,
             role_rows: Support.load_roles(),
             role_form: Support.empty_role_form(),
             role_feedback: "角色已删除"
           )}

        error ->
          {:noreply, assign(socket, role_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-menus", _params, socket) do
    if Support.admin_socket?(socket) do
      {:noreply,
       assign(socket,
         menu_rows: Support.load_menus(),
         menu_form: Support.empty_menu_form(),
         menu_feedback: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-menu", _params, socket) do
    if Support.admin_socket?(socket) do
      {:noreply, assign(socket, menu_form: Support.empty_menu_form(), menu_feedback: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-menu", %{"menu-id" => menu_id}, socket) do
    if Support.admin_socket?(socket) do
      case Enum.find(socket.assigns.menu_rows, &(to_string(&1["menuId"]) == menu_id)) do
        nil ->
          {:noreply, assign(socket, menu_feedback: "找不到指定菜单")}

        menu ->
          form =
            menu
            |> Map.merge(Support.empty_menu_form())
            |> Map.put("metaInfo", Jason.encode!(menu["meta"] || %{}))
            |> Map.put("isButton", if(menu["isButton"] == 1, do: "true", else: "false"))

          {:noreply, assign(socket, menu_form: form, menu_feedback: nil)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-menu", params, socket) do
    if Support.admin_socket?(socket) do
      menu_id = String.trim(params["menuId"] || "")

      result =
        if menu_id == "", do: Menu.create_menu(params), else: Menu.update_menu(menu_id, params)

      case result do
        {:ok, _menu} ->
          {:noreply,
           assign(socket,
             menu_rows: Support.load_menus(),
             menu_form: Support.empty_menu_form(),
             menu_feedback: if(menu_id == "", do: "菜单已创建", else: "菜单已更新")
           )}

        error ->
          {:noreply, assign(socket, menu_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-menu-status", %{"menu-id" => menu_id, "status" => status}, socket) do
    if Support.admin_socket?(socket) do
      case Menu.update_menu(menu_id, %{"status" => status}) do
        {:ok, _menu} ->
          {:noreply, assign(socket, menu_rows: Support.load_menus(), menu_feedback: "菜单状态已更新")}

        error ->
          {:noreply, assign(socket, menu_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-menu", %{"menu-id" => menu_id}, socket) do
    if Support.admin_socket?(socket) do
      case Menu.delete_menu(menu_id) do
        {:ok, _} ->
          {:noreply,
           assign(socket,
             menu_rows: Support.load_menus(),
             menu_form: Support.empty_menu_form(),
             menu_feedback: "菜单已删除"
           )}

        :ok ->
          {:noreply,
           assign(socket,
             menu_rows: Support.load_menus(),
             menu_form: Support.empty_menu_form(),
             menu_feedback: "菜单已删除"
           )}

        error ->
          {:noreply, assign(socket, menu_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end
end
