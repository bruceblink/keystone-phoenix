defmodule KeystonePhoenixWeb.ConfigController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      list: "config:read",
      show: "config:read",
      create: "config:create",
      update: "config:update",
      delete: "config:update",
      refresh_cache: "config:refresh"
    }

  plug KeystonePhoenixWeb.Plugs.RequireResourceScope, resource: :config

  alias KeystonePhoenix.Config
  alias KeystonePhoenixWeb.ApiResponse
  alias KeystonePhoenixWeb.ManagementContract

  @doc "Returns a paginated list of system configuration entries."
  def list(conn, params) do
    authorization = [authorization: %{principal: conn.assigns.current_user}]

    if paged_request?(params) do
      case Config.list_configs_page(paging_params(params), authorization) do
        {:ok, page} ->
          data = %{
            items: Enum.map(page.items, &ManagementContract.config/1),
            page: page.page,
            size: page.size,
            total: page.total
          }

          json(conn, ApiResponse.ok(data))

        {:error, reason} ->
          render_error(conn, reason)
      end
    else
      case Config.list_configs_all(params, authorization) do
        {:ok, rows} ->
          json(conn, ApiResponse.ok(Enum.map(rows, &ManagementContract.config/1)))

        {:error, reason} ->
          render_error(conn, reason)
      end
    end
  end

  @doc "Returns a system configuration entry."
  def show(conn, %{"config_id" => config_id}) do
    case Config.get_config(config_id, authorization: %{principal: conn.assigns.current_user}) do
      {:ok, config} ->
        json(conn, ApiResponse.ok(Config.config_to_map(config) |> ManagementContract.config()))

      {:error, :not_found} ->
        render_error(conn, :not_found)

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @doc "Creates a system configuration entry."
  def create(conn, params) do
    params = ManagementContract.config_params(params)

    case Config.create_config(params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, config} ->
        conn
        |> put_status(:created)
        |> json(ApiResponse.ok(Config.config_to_map(config) |> ManagementContract.config()))

      {:error, changeset} ->
        render_error(conn, changeset)
    end
  end

  @doc "Updates the value of a system configuration entry."
  def update(conn, %{"config_id" => config_id} = params) do
    params =
      params
      |> ManagementContract.config_params()
      |> Map.drop(["key", "configKey"])

    case Config.update_native_config(config_id, params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, config} ->
        json(conn, ApiResponse.ok(Config.config_to_map(config) |> ManagementContract.config()))

      {:error, :not_found} ->
        render_error(conn, :not_found)

      {:error, :not_allow_change} ->
        render_error(conn, :not_allow_change)

      {:error, changeset} ->
        render_error(conn, changeset)
    end
  end

  @doc "Soft deletes a system configuration entry."
  def delete(conn, %{"config_id" => config_id}) do
    case Config.delete_config(config_id,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, _config} -> json(conn, ApiResponse.ok(%{"deleted" => true}))
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, reason} -> render_error(conn, reason)
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
    |> json(ApiResponse.error(:resource_not_found, "找不到请求的系统配置"))
  end

  defp render_error(conn, :not_allow_change) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "该配置不允许修改"))
  end

  defp render_error(conn, :permission_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:permission_denied, "没有操作权限"))
  end

  defp render_error(conn, :data_scope_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:data_scope_denied, "没有数据权限"))
  end

  defp render_error(conn, changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "参数校验失败", errors))
  end

  defp paged_request?(params), do: Map.has_key?(params, "page") or Map.has_key?(params, "size")

  defp paging_params(params) do
    params
    |> Map.put_new("pageNum", params["page"] || "1")
    |> Map.put_new("pageSize", params["size"] || "20")
  end
end
