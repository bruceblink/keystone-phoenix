defmodule KeystonePhoenixWeb.DictionaryController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      list_types: "dictionary:read",
      list_data: "dictionary:read",
      list_data_by_type: "dictionary:read",
      show_type: "dictionary:read",
      show_data: "dictionary:read",
      create_type: "dictionary:create",
      update_type: "dictionary:update",
      delete_type: "dictionary:delete",
      create_data: "dictionary:create",
      update_data: "dictionary:update",
      delete_data: "dictionary:delete",
      refresh_cache: "dictionary:refresh"
    }

  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns a paginated list of dictionary types."
  def list_types(conn, params) do
    json(conn, ApiResponse.ok(Dictionary.list_dict_types(params)))
  end

  @doc "Returns a paginated list of dictionary items."
  def list_data(conn, params) do
    json(conn, ApiResponse.ok(Dictionary.list_dict_data(params)))
  end

  @doc "Returns active dictionary items for a select component."
  def list_data_by_type(conn, %{"dict_type" => dict_type}) do
    json(conn, ApiResponse.ok(Dictionary.list_dict_data_by_type(dict_type)))
  end

  def show_type(conn, %{"dict_id" => dict_id}) do
    case Dictionary.get_dict_type(dict_id) do
      {:ok, dict_type} -> json(conn, ApiResponse.ok(Dictionary.dict_type_to_map(dict_type)))
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  def show_data(conn, %{"dict_code" => dict_code}) do
    case Dictionary.get_dict_data(dict_code) do
      {:ok, dict_data} -> json(conn, ApiResponse.ok(Dictionary.dict_data_to_map(dict_data)))
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  def create_type(conn, params) do
    case Dictionary.create_dict_type(params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, _dict_type} -> conn |> put_status(:created) |> json(ApiResponse.ok())
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def update_type(conn, %{"dict_id" => dict_id} = params) do
    case Dictionary.update_dict_type(dict_id, params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, _dict_type} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def delete_type(conn, %{"dict_id" => dict_id}) do
    case Dictionary.delete_dict_type(dict_id,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, :has_data} -> render_error(conn, :has_data)
    end
  end

  def create_data(conn, params) do
    case Dictionary.create_dict_data(params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, _dict_data} -> conn |> put_status(:created) |> json(ApiResponse.ok())
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def update_data(conn, %{"dict_code" => dict_code} = params) do
    case Dictionary.update_dict_data(dict_code, params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, _dict_data} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def delete_data(conn, %{"dict_code" => dict_code}) do
    case Dictionary.delete_dict_data(dict_code,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  @doc "Clears cached dictionary data values."
  def refresh_cache(conn, _params) do
    case Dictionary.refresh_cache(authorization: %{principal: conn.assigns.current_user}) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(10001, "找不到请求的字典数据"))
  end

  defp render_error(conn, :has_data) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(11101, "字典类型下存在字典数据，请先删除字典数据"))
  end

  defp render_error(conn, :dict_type_not_found) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(11102, "字典类型不存在或已停用"))
  end

  defp render_error(conn, changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(99999, "参数校验失败", errors))
  end
end
