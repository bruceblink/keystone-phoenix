defmodule KeystonePhoenixWeb.ProfileController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate

  alias KeystonePhoenix.Upload
  alias KeystonePhoenix.User
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns the authenticated user's profile."
  def show(conn, _params) do
    case User.profile(conn.assigns.current_user.user_id) do
      {:ok, profile} -> json(conn, ApiResponse.ok(profile))
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  @doc "Updates the authenticated user's profile."
  def update(conn, params) do
    case User.update_profile(
           conn.assigns.current_user.user_id,
           params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, _user} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Changes the authenticated user's password."
  def update_password(conn, params) do
    case User.update_password(
           conn.assigns.current_user.user_id,
           params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, _user} -> json(conn, ApiResponse.ok())
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
          json(conn, ApiResponse.ok(%{"imgUrl" => avatar_url}))

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

  def update_avatar(conn, %{"avatar" => avatar}) do
    with {:ok, current_user} <- User.get_user(conn.assigns.current_user.user_id) do
      case User.update_avatar(
             conn.assigns.current_user.user_id,
             avatar,
             authorization: %{principal: conn.assigns.current_user}
           ) do
        {:ok, _user} ->
          delete_previous_avatar(current_user.avatar, avatar)
          json(conn, ApiResponse.ok(%{"imgUrl" => avatar}))

        {:error, :not_found} ->
          render_error(conn, :not_found)

        {:error, changeset} ->
          render_error(conn, changeset)
      end
    else
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  def update_avatar(conn, _params), do: render_error(conn, :invalid_avatar)

  defp render_error(conn, :not_found) do
    conn |> put_status(:not_found) |> json(ApiResponse.error(10001, "找不到当前用户"))
  end

  defp render_error(conn, :invalid_old_password) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(10007, "旧密码错误"))
  end

  defp render_error(conn, :same_password) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(10008, "新密码不能与旧密码相同"))
  end

  defp render_error(conn, :unavailable) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(50301, "认证会话暂不可用"))
  end

  defp render_error(conn, :invalid_avatar) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(10009, "头像地址无效"))
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
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(10009, "头像文件无效"))
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(99999, "参数校验失败", errors))
  end

  defp delete_previous_avatar(previous, current)
       when is_binary(previous) and is_binary(current) and previous != current do
    if String.starts_with?(previous, "/profile/avatar/"), do: Upload.delete_avatar(previous)
    :ok
  end

  defp delete_previous_avatar(_previous, _current), do: :ok
end
