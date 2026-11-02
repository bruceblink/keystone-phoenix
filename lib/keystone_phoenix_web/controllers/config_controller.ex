defmodule KeystonePhoenixWeb.ConfigController do
  use KeystonePhoenixWeb, :controller

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
    case Config.create_config(params) do
      {:ok, _config} -> conn |> put_status(:created) |> json(ApiResponse.ok())
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Updates the value of a system configuration entry."
  def update(conn, %{"config_id" => config_id} = params) do
    case Config.update_config(config_id, params) do
      {:ok, _config} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Clears cached configuration values."
  def refresh_cache(conn, _params) do
    Config.refresh_cache()
    json(conn, ApiResponse.ok())
  end

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(10001, "找不到请求的系统配置"))
  end

  defp render_error(conn, changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(99999, "参数校验失败", errors))
  end
end
