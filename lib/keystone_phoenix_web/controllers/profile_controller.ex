defmodule KeystonePhoenixWeb.ProfileController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.RejectApiKey

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      show: "user:read",
      update: "user:update",
      update_password: "user:reset-password",
      update_avatar: "user:update"
    }

  # 修改个人密码会撤销现有会话，必须使用 AAL2 会话。
  plug KeystonePhoenixWeb.Plugs.RequireMfaStepUp when action in [:update_password]
  plug KeystonePhoenixWeb.Plugs.RequireResourceScope, resource: :profile

  alias KeystonePhoenix.Upload
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.PasswordPolicy
  alias KeystonePhoenixWeb.ApiResponse
  alias KeystonePhoenixWeb.NativeObservabilityContract

  @doc "Returns the authenticated user's profile."
  def show(conn, _params) do
    case User.profile(conn.assigns.current_user.user_id) do
      {:ok, %{"user" => user}} ->
        json(conn, ApiResponse.ok(NativeObservabilityContract.profile(user)))

      {:error, :not_found} ->
        render_error(conn, :not_found)
    end
  end

  @doc "Updates the authenticated user's profile."
  def update(conn, params) do
    case User.update_profile(
           conn.assigns.current_user.user_id,
           params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, user} ->
        json(
          conn,
          ApiResponse.ok(
            NativeObservabilityContract.profile(User.user_to_map_with_relations(user))
          )
        )

      {:error, :not_found} ->
        render_error(conn, :not_found)

      {:error, :display_name_required} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ApiResponse.error(:profile_display_name_required, "displayName is required"))

      {:error, changeset} ->
        render_error(conn, changeset)
    end
  end

  @doc "Changes the authenticated user's password."
  def update_password(conn, params) do
    case User.update_password(
           conn.assigns.current_user.user_id,
           params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, _user} -> json(conn, ApiResponse.ok(%{"updated" => true}))
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, :invalid_old_password} -> render_error(conn, :invalid_old_password)
      {:error, :same_password} -> render_error(conn, :same_password)
      {:error, :unavailable} -> render_error(conn, :unavailable)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Uploads an avatar using the original multipart avatarfile contract."
  def update_avatar(conn, %{"avatarfile" => %Plug.Upload{} = upload}) do
    with {:ok, current_user} <- User.get_user(conn.assigns.current_user.user_id),
         {:ok, avatar_url} <- Upload.store_avatar(upload) do
      case User.update_avatar(
             conn.assigns.current_user.user_id,
             avatar_url,
             authorization: %{principal: conn.assigns.current_user}
           ) do
        {:ok, _user} ->
          delete_previous_avatar(current_user.avatar, avatar_url)
          json(conn, ApiResponse.ok(%{"avatar" => avatar_url}))

        {:error, :not_found} ->
          Upload.delete_avatar(avatar_url)
          render_error(conn, :not_found)

        {:error, reason} ->
          Upload.delete_avatar(avatar_url)
          render_error(conn, reason)
      end
    else
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def update_avatar(conn, %{"avatar" => avatar}) when is_binary(avatar) do
    with {:ok, current_user} <- User.get_user(conn.assigns.current_user.user_id) do
      case User.update_avatar(
             conn.assigns.current_user.user_id,
             avatar,
             authorization: %{principal: conn.assigns.current_user}
           ) do
        {:ok, _user} ->
          delete_previous_avatar(current_user.avatar, avatar)
          json(conn, ApiResponse.ok(%{"avatar" => avatar}))

        {:error, :not_found} ->
          render_error(conn, :not_found)

        {:error, changeset} ->
          render_error(conn, changeset)
      end
    else
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  # 非字符串头像地址与缺失地址使用相同的业务错误，避免进入 User.update_avatar 的二进制子句。
  def update_avatar(conn, %{"avatar" => _invalid}),
    do: render_error(conn, :profile_avatar_required)

  def update_avatar(conn, %{"avatarfile" => _invalid}), do: render_error(conn, :invalid_upload)
  def update_avatar(conn, _params), do: render_error(conn, :profile_avatar_required)

  defp render_error(conn, :not_found) do
    conn |> put_status(:not_found) |> json(ApiResponse.error(:resource_not_found, "找不到当前用户"))
  end

  defp render_error(conn, :invalid_old_password) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "旧密码错误"))
  end

  defp render_error(conn, :same_password) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:password_same_as_current, "新密码不能与当前密码相同"))
  end

  defp render_error(conn, :unavailable) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(:authorization_unavailable, "认证会话暂不可用"))
  end

  defp render_error(conn, :profile_avatar_required) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:profile_avatar_required, "avatar is required"))
  end

  defp render_error(conn, reason)
       when reason in [
              :invalid_upload,
              :empty_upload,
              :file_too_large,
              :filename_too_long,
              :type_not_allowed,
              :storage_error
            ] do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "头像文件无效"))
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    case PasswordPolicy.error_code(changeset) do
      nil ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(ApiResponse.error(:validation_failed, "参数校验失败", errors))

      code ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ApiResponse.error(code, "密码不符合安全策略"))
    end
  end

  defp delete_previous_avatar(previous, current)
       when is_binary(previous) and is_binary(current) and previous != current do
    if String.starts_with?(previous, "/profile/avatar/"), do: Upload.delete_avatar(previous)
    :ok
  end

  defp delete_previous_avatar(_previous, _current), do: :ok
end
