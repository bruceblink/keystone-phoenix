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
          url: '/openapi',
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

        operation = %{
          "summary" => "#{inspect(route.plug)} #{inspect(route.plug_opts)}",
          "operationId" => operation_id(route),
          "responses" => %{"200" => %{"description" => "成功"}}
        }

        Map.update(acc, path, %{method => operation}, &Map.put(&1, method, operation))
      end)

    json(conn, %{
      "openapi" => "3.0.3",
      "info" => %{"title" => "Keystone API", "version" => "v1"},
      "servers" => [%{"url" => "/api/v1"}],
      "paths" => paths
    })
  end

  defp documented_route?(route) do
    route.verb in ~w(get post put patch delete)a and String.starts_with?(route.path, "/api/v1/")
  end

  defp normalize_path(path), do: Regex.replace(~r/:([a-zA-Z0-9_]+)/, path, "{\\1}")

  defp operation_id(route) do
    plug = route.plug |> Module.split() |> Enum.join("_")
    "#{plug}_#{route.plug_opts}"
  end
end
