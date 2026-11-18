defmodule KeystonePhoenixWeb.ApiDocsController do
  use KeystonePhoenixWeb, :controller

  @swagger_html """
  <!doctype html>
  <html lang="zh-CN">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>Keystone API 文档</title>
      <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
    </head>
    <body>
      <div id="swagger-ui"></div>
      <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
      <script>
        window.onload = () => window.ui = SwaggerUIBundle({
          url: '/api/openapi',
          dom_id: '#swagger-ui',
          deepLinking: true,
          presets: [SwaggerUIBundle.presets.apis],
          layout: 'BaseLayout'
        });
      </script>
    </body>
  </html>
  """

  @doc "返回 Swagger UI 页面。"
  def swagger(conn, _params), do: html(conn, @swagger_html)

  @doc "根据当前 Phoenix 路由生成可供 Swagger UI 展示的 OpenAPI 路径目录。"
  def openapi(conn, _params) do
    paths =
      KeystonePhoenixWeb.Router.__routes__()
      |> Enum.filter(&documented_route?/1)
      |> Enum.reduce(%{}, fn route, acc ->
        path = normalize_path(route.path)
        method = Atom.to_string(route.verb)

        operation =
          %{
            "summary" => "#{inspect(route.plug)} #{inspect(route.plug_opts)}",
            "operationId" => operation_id(route),
            "responses" => %{"200" => %{"description" => "成功"}}
          }
          |> document_notification_paging(route)

        Map.update(acc, path, %{method => operation}, &Map.put(&1, method, operation))
      end)

    json(conn, %{
      "openapi" => "3.0.3",
      "info" => %{"title" => "Keystone API", "version" => "v1"},
      "servers" => [%{"url" => "/"}],
      "paths" => paths
    })
  end

  defp documented_route?(route) do
    route.verb in ~w(get post put patch delete)a and String.starts_with?(route.path, "/api/v1/")
  end

  # 旧通知列表不带分页字段；显式 page 请求返回页码和是否有下一页。
  defp document_notification_paging(operation, %{verb: :get, path: "/api/v1/notifications"}) do
    operation
    |> Map.put(
      "description",
      "不传 page 时返回最近 50 条通知；传 page 时按每页 50 条返回 page、hasMore 和全部未读数。无效页码按第 1 页处理。"
    )
    |> Map.put("parameters", [
      %{
        "name" => "page",
        "in" => "query",
        "required" => false,
        "description" => "页码，范围 1 至 1000000；不传时使用兼容响应。",
        "schema" => %{"type" => "integer", "minimum" => 1, "maximum" => 1_000_000}
      }
    ])
  end

  defp document_notification_paging(operation, _route), do: operation

  defp normalize_path(path), do: Regex.replace(~r/:([a-zA-Z0-9_]+)/, path, "{\\1}")

  defp operation_id(route) do
    plug = route.plug |> Module.split() |> Enum.join("_")
    "#{plug}_#{route.plug_opts}"
  end
end
