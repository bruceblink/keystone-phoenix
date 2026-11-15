defmodule KeystonePhoenixWeb.ApiDocsControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: true

  test "serves Swagger UI and an OpenAPI route directory", %{conn: conn} do
    swagger = get(conn, "/swagger")
    assert swagger.status == 200
    assert swagger.resp_body =~ "SwaggerUIBundle"

    openapi = get(build_conn(), "/openapi")
    body = json_response(openapi, 200)
    assert body["openapi"] == "3.0.3"
    assert is_map(body["paths"])
    assert Map.has_key?(body["paths"], "/api/v1/users")
  end

  test "does not expose the old documentation path" do
    assert get(build_conn(), "/api-docs").status == 404
  end
end
