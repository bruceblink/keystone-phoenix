defmodule KeystonePhoenixWeb.Live.AdminEvents.Accounts do
  @moduledoc "LiveView event handlers for the accounts domain."

  import Phoenix.Component, only: [assign: 2]
  alias KeystonePhoenix.User
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def handle_event("refresh-users", _params, socket) do
    if Support.admin_socket?(socket) do
      {:noreply,
       assign(socket,
         user_rows: Support.load_users(),
         user_form: Support.empty_user_form(),
         user_feedback: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-user", _params, socket) do
    if Support.admin_socket?(socket) do
      {:noreply, assign(socket, user_form: Support.empty_user_form(), user_feedback: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-user", %{"user-id" => user_id}, socket) do
    if Support.admin_socket?(socket) do
      case Enum.find(socket.assigns.user_rows, &(to_string(&1["userId"]) == user_id)) do
        nil ->
          {:noreply, assign(socket, user_feedback: "找不到指定用户")}

        user ->
          {:noreply,
           assign(socket,
             user_form: Map.merge(Support.empty_user_form(), user),
             user_feedback: nil
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-user", params, socket) do
    if Support.admin_socket?(socket) do
      user_id = String.trim(params["userId"] || "")
      params = if user_id == "", do: params, else: Map.delete(params, "password")

      result =
        if user_id == "", do: User.create_user(params), else: User.update_user(user_id, params)

      case result do
        {:ok, _user} ->
          {:noreply,
           assign(socket,
             user_rows: Support.load_users(),
             role_rows: Support.load_roles(),
             user_form: Support.empty_user_form(),
             user_feedback: if(user_id == "", do: "用户已创建", else: "用户已更新")
           )}

        error ->
          {:noreply, assign(socket, user_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-user-status", %{"user-id" => user_id, "status" => status}, socket) do
    if Support.admin_socket?(socket) do
      case User.change_status(user_id, status) do
        {:ok, _user} ->
          {:noreply, assign(socket, user_rows: Support.load_users(), user_feedback: "用户状态已更新")}

        error ->
          {:noreply, assign(socket, user_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-user", %{"user-id" => user_id}, socket) do
    if Support.admin_socket?(socket) do
      case User.delete_users([user_id], socket.assigns.current_user["userId"]) do
        :ok ->
          {:noreply,
           assign(socket,
             user_rows: Support.load_users(),
             role_rows: Support.load_roles(),
             user_form: Support.empty_user_form(),
             user_feedback: "用户已删除"
           )}

        error ->
          {:noreply, assign(socket, user_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("reset-user-password", %{"user-id" => user_id, "password" => password}, socket) do
    if Support.admin_socket?(socket) do
      case User.reset_password(user_id, %{"password" => password}) do
        {:ok, _user} -> {:noreply, assign(socket, user_feedback: "用户密码已重置")}
        error -> {:noreply, assign(socket, user_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-profile", params, socket) do
    if Support.authenticated_socket?(socket) do
      user_id = socket.assigns.current_user["userId"]

      case User.update_profile(user_id, params) do
        {:ok, _user} ->
          case User.profile(user_id) do
            {:ok, profile} ->
              {:noreply,
               assign(socket,
                 current_user: profile,
                 profile_form: profile,
                 profile_feedback: "个人资料已保存"
               )}

            _ ->
              {:noreply, assign(socket, profile_feedback: "个人资料已保存")}
          end

        error ->
          {:noreply, assign(socket, profile_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("change-profile-password", params, socket) do
    if Support.authenticated_socket?(socket) do
      case User.update_password(socket.assigns.current_user["userId"], params) do
        {:ok, _user} ->
          {:noreply,
           assign(socket,
             password_form: Support.empty_password_form(),
             profile_feedback: "密码已更新，请重新登录"
           )}

        error ->
          {:noreply, assign(socket, profile_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("update-profile-avatar", %{"avatar" => avatar}, socket) do
    if Support.authenticated_socket?(socket) do
      case User.update_avatar(socket.assigns.current_user["userId"], avatar) do
        {:ok, _user} ->
          {:noreply,
           assign(socket,
             profile_form: Map.put(socket.assigns.profile_form, "avatar", avatar),
             profile_feedback: "头像地址已更新"
           )}

        error ->
          {:noreply, assign(socket, profile_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end
end
