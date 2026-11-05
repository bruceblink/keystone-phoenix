defmodule KeystonePhoenixWeb.ResourceController do
  use KeystonePhoenixWeb, :controller

  alias KeystonePhoenix.Upload

  @image_extensions ~w(bmp gif jpg jpeg png webp)

  @doc "Serves uploaded profile resources from the configured local directory."
  def show(conn, %{"path" => path}) do
    case Upload.resolve_profile_path(path) do
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

  def show(conn, _params), do: send_resp(conn, :not_found, "Not found")
end
