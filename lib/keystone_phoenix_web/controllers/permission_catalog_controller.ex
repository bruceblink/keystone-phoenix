defmodule KeystonePhoenixWeb.PermissionCatalogController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate, permissions: %{index: "api-key:create"}

  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Authz.PermissionCatalog
  alias KeystonePhoenixWeb.ApiResponse

  @doc "返回 API Key 和角色配置使用的动态权限目录。"
  def index(conn, _params) do
    entries =
      Enum.map(PermissionCatalog.entries(), fn entry ->
        %{
          "permission" => entry.permission,
          "resource" => entry.resource,
          "action" => entry.action,
          "description" => entry.description,
          "risk" => to_string(entry.risk),
          "registered" => entry.registered?,
          "allowed" =>
            Authz.allowed?(conn.assigns.current_user, entry.permission, %{connection: conn})
        }
      end)

    json(conn, ApiResponse.ok(%{"entries" => entries}))
  end
end
