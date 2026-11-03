defmodule KeystonePhoenixWeb.ResourceController do
  use KeystonePhoenixWeb, :controller

  alias KeystonePhoenix.Upload

  @doc "Serves uploaded profile resources from the configured local directory."
  def show(conn, %{"path" => path}) do
    case Upload.resolve_profile_path(path) do
      {:ok, file} ->
        conn
        |> put_resp_content_type(MIME.from_path(file))
        |> put_resp_header("cache-control", "public, max-age=31536000")
        |> send_file(200, file)

      {:error, :not_found} ->
        send_resp(conn, :not_found, "Not found")
    end
  end

  def show(conn, _params), do: send_resp(conn, :not_found, "Not found")
end
