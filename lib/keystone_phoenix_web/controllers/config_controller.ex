defmodule KeystonePhoenixWeb.ConfigController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      list: "system:config:list",
      show: "system:config:query",
      create: "system:config:add",
      update: "system:config:edit",
      refresh_cache: "system:config:refresh"
    }

  alias KeystonePhoenix.Config
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns a paginated list of system configuration entries."
  def list(conn, params) do
    json(conn, ApiResponse.ok(Config.list_configs(params)))
  end

  @doc "Returns a system configuration entry."
  def show(conn, %{"config_id" => config_id}) do
    case Config.get_config(config_id) do
      {:ok, config} -> json(conn, ApiResponse.ok(Config.config_to_map(config)))
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  @doc "Creates a system configuration entry."
  def create(conn, params) do
    case Config.create_config(params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, _config} -> conn |> put_status(:created) |> json(ApiResponse.ok())
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Updates the value of a system configuration entry."
  def update(conn, %{"config_id" => config_id} = params) do
    case Config.update_config(config_id, params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, _config} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, :not_allow_change} -> render_error(conn, :not_allow_change)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Clears cached configuration values."
  def refresh_cache(conn, _params) do
    case Config.refresh_cache(authorization: %{principal: conn.assigns.current_user}) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(10001, "找不到请求的系统配置"))
  end

  defp render_error(conn, :not_allow_change) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(10002, "该配置不允许修改"))
  end

  defp render_error(conn, changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(99999, "参数校验失败", errors))
  end
end
