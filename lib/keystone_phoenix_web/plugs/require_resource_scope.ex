defmodule KeystonePhoenixWeb.Plugs.RequireResourceScope do
  @moduledoc "在已认证的控制器入口统一检查资源数据范围。"

  import Plug.Conn

  alias KeystonePhoenix.Authz
  alias KeystonePhoenixWeb.ApiResponse

  def init(opts), do: opts

  def call(conn, opts) do
    resource = Keyword.fetch!(opts, :resource)
    principal = conn.assigns[:current_user]
    context = context(conn, opts)

    if Authz.resource_scope_allowed?(principal, resource, context) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.json(ApiResponse.error(:data_scope_denied, "没有数据权限"))
      |> halt()
    end
  end

  defp context(conn, opts) do
    context =
      case Keyword.get(opts, :owner_param) do
        nil -> %{}
        key -> %{owner_id: Map.get(conn.params, key, Map.get(conn.params, to_string(key)))}
      end

    if Keyword.get(opts, :defer_owner, false),
      do: Map.put(context, :defer_owner, true),
      else: context
  end
end
