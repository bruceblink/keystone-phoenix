defmodule KeystonePhoenixWeb.ResourceController do
  use KeystonePhoenixWeb, :controller

  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Upload

  @image_extensions ~w(bmp gif jpg jpeg png webp)

  @doc "Serves public avatar images from the configured local directory."
  def avatar(conn, %{"path" => path}) do
    case Upload.resolve_profile_path(["avatar" | List.wrap(path)]) do
      {:ok, file} ->
        extension = file |> Path.extname() |> String.trim_leading(".") |> String.downcase()

        if extension in @image_extensions do
          conn
          |> put_resp_content_type(MIME.from_path(file))
          |> put_resp_header("x-content-type-options", "nosniff")
          |> put_resp_header("cache-control", "public, max-age=31536000")
          |> send_file(200, file)
        else
          send_resp(conn, :not_found, "Not found")
        end

      {:error, :not_found} ->
        send_resp(conn, :not_found, "Not found")
    end
  end

  def avatar(conn, _params), do: send_resp(conn, :not_found, "Not found")

  @doc "Serves uploaded profile resources from the configured local directory."
  def show(conn, %{"path" => path}) do
    case owner_scoped_path(path) do
      {:ok, owner_id, relative_path} ->
        if owner_allowed?(conn.assigns[:current_user], owner_id) do
          send_profile_file(conn, relative_path)
        else
          send_resp(conn, :forbidden, "Forbidden")
        end

      :error ->
        send_resp(conn, :not_found, "Not found")
    end
  end

  def show(conn, _params), do: send_resp(conn, :not_found, "Not found")

  defp owner_scoped_path(["upload", owner | rest]) when rest != [] do
    if Enum.any?(rest, &unsafe_segment?/1) do
      :error
    else
      case Params.parse_uuid(owner) do
        {:ok, owner_id} -> {:ok, owner_id, ["upload", owner | rest]}
        :error -> :error
      end
    end
  end

  defp owner_scoped_path(_path), do: :error

  defp unsafe_segment?(segment),
    do: segment in [".", ".."] or String.contains?(to_string(segment), ["\\", "\0"])

  defp owner_allowed?(principal, owner_id) when is_map(principal) do
    Authz.scope_allowed?(principal, :self, owner_id)
  end

  defp owner_allowed?(_principal, _owner_id), do: false

  defp send_profile_file(conn, path) do
    case Upload.resolve_profile_path(path) do
      {:ok, file} ->
        extension = file |> Path.extname() |> String.trim_leading(".") |> String.downcase()
        send_file_response(conn, file, extension in @image_extensions)

      {:error, :not_found} ->
        send_resp(conn, :not_found, "Not found")
    end
  end

  defp send_file_response(conn, file, true) do
    conn
    |> put_resp_content_type(MIME.from_path(file))
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("cache-control", "public, max-age=31536000")
    |> send_file(200, file)
  end

  defp send_file_response(conn, file, false) do
    conn
    |> put_resp_content_type("application/octet-stream")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="#{Path.basename(file)}")
    )
    |> send_file(200, file)
  end
end
