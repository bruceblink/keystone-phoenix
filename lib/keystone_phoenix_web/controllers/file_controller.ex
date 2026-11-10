defmodule KeystonePhoenixWeb.FileController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate

  alias KeystonePhoenix.Upload
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Uploads one generic file."
  def upload(conn, %{"file" => %Plug.Upload{} = file}) do
    case Upload.store_file(file) do
      {:ok, upload} -> json(conn, ApiResponse.ok(upload))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def upload(conn, _params), do: render_error(conn, :empty_upload)

  @doc "Uploads multiple generic files."
  def uploads(conn, %{"files" => files}) when is_list(files) do
    case Upload.store_files(files) do
      {:ok, uploads} -> json(conn, ApiResponse.ok(uploads))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def uploads(conn, _params), do: render_error(conn, :empty_upload)

  @doc "Downloads a file from the configured download directory."
  def download(conn, %{"fileName" => file_name}) do
    case Upload.resolve_download_path(file_name) do
      {:ok, path} ->
        conn
        |> put_resp_content_type("application/octet-stream")
        |> put_resp_header(
          "content-disposition",
          ~s(attachment; filename="#{Path.basename(path)}")
        )
        |> send_file(200, path)

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def download(conn, _params), do: render_error(conn, :invalid_file_name)

  defp render_error(conn, reason) when reason in [:empty_upload, :invalid_upload] do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(40001, "上传文件不能为空"))
  end

  defp render_error(conn, reason)
       when reason in [:file_too_large, :filename_too_long, :type_not_allowed, :too_many_files] do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(40002, "文件类型或大小无效"))
  end

  defp render_error(conn, :not_found) do
    conn |> put_status(:not_found) |> json(ApiResponse.error(40401, "文件不存在"))
  end

  defp render_error(conn, reason) when reason in [:invalid_file_name, :storage_error] do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(40003, "文件路径无效"))
  end
end
