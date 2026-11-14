defmodule KeystonePhoenixWeb.ExcelResponse do
  @moduledoc "Renders XLSX downloads using the existing API error envelope."

  import Plug.Conn

  alias KeystonePhoenix.Excel
  alias KeystonePhoenixWeb.ApiResponse

  @content_type "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

  @spec send_xlsx(Plug.Conn.t(), String.t(), [term()], [[term()]]) :: Plug.Conn.t()
  def send_xlsx(conn, filename, headers, rows) do
    case Excel.export(headers, rows, filename) do
      {:ok, binary} ->
        send_xlsx(conn, filename, binary)

      {:error, _reason} ->
        render_error(conn, "Excel 导出失败")
    end
  end

  @doc "Sends an already validated XLSX workbook to an HTTP or LiveView caller."
  @spec send_xlsx(Plug.Conn.t(), String.t(), binary()) :: Plug.Conn.t()
  def send_xlsx(conn, filename, binary) when is_binary(binary) do
    conn
    |> put_resp_content_type(@content_type)
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, binary)
  end

  @spec render_error(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def render_error(conn, message) do
    conn
    |> put_status(:unprocessable_entity)
    |> Phoenix.Controller.json(ApiResponse.error(:validation_failed, message))
  end
end
