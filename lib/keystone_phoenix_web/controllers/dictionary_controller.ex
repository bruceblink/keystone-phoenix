defmodule KeystonePhoenixWeb.DictionaryController do
  use KeystonePhoenixWeb, :controller

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
    case Dictionary.create_dict_type(params) do
      {:ok, _dict_type} -> conn |> put_status(:created) |> json(ApiResponse.ok())
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def update_type(conn, %{"dict_id" => dict_id} = params) do
    case Dictionary.update_dict_type(dict_id, params) do
      {:ok, _dict_type} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def delete_type(conn, %{"dict_id" => dict_id}) do
    case Dictionary.delete_dict_type(dict_id) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, :has_data} -> render_error(conn, :has_data)
    end
  end

  def create_data(conn, params) do
    case Dictionary.create_dict_data(params) do
      {:ok, _dict_data} -> conn |> put_status(:created) |> json(ApiResponse.ok())
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def update_data(conn, %{"dict_code" => dict_code} = params) do
    case Dictionary.update_dict_data(dict_code, params) do
      {:ok, _dict_data} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def delete_data(conn, %{"dict_code" => dict_code}) do
    case Dictionary.delete_dict_data(dict_code) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
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

  defp render_error(conn, changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(99999, "参数校验失败", errors))
  end
end
