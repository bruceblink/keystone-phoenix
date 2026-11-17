defmodule KeystonePhoenixWeb.Live.AdminEvents.Profile do
  @moduledoc "已登录用户的个人资料 LiveView 事件。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.User
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def handle_event(params, socket) do
    if Support.authenticated_socket?(socket) do
      user_id = socket.assigns.current_user["userId"]
      profile_params = normalize_profile_params(params)

      case User.update_profile(
             user_id,
             profile_params,
             Support.authorization_options(socket)
           ) do
        {:ok, _user} ->
          refresh_profile(socket, user_id)

        {:error, :display_name_required} ->
          {:noreply,
           assign(socket,
             profile_form: Map.merge(socket.assigns.profile_form, profile_params),
             profile_feedback: Feedback.error(:validation_failed, "展示名不能为空")
           )}

        error ->
          {:noreply,
           assign(socket,
             profile_form: Map.merge(socket.assigns.profile_form, profile_params),
             profile_feedback: Support.form_error(error)
           )}
      end
    else
      {:noreply, socket}
    end
  end

  # 保存成功后使用服务端资料刷新表单和顶栏身份。
  defp refresh_profile(socket, user_id) do
    case User.profile(user_id) do
      {:ok, profile} ->
        profile_user = profile["user"] || profile

        {:noreply,
         assign(socket,
           current_user: profile_user,
           profile_form: profile_user,
           profile_feedback: "个人资料已保存"
         )}

      _ ->
        {:noreply, assign(socket, profile_feedback: "个人资料已保存")}
    end
  end

  # 将空性别选项映射为 Phoenix 数据模型使用的未知值 2。
  defp normalize_profile_params(params) when is_map(params) do
    case Map.get(params, "sex") do
      "" -> Map.put(params, "sex", "2")
      _ -> params
    end
  end
end
