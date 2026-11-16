defmodule KeystonePhoenixWeb.DictionaryController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      list_types: "dictionary:read",
      list_data_by_type: "dictionary:read",
      create_type: "dictionary:create",
      update_type: "dictionary:update",
      delete_type: "dictionary:delete",
      create_data: "dictionary:create",
      update_data: "dictionary:update",
      delete_data: "dictionary:delete"
    }

  plug KeystonePhoenixWeb.Plugs.RequireResourceScope, resource: :dictionary

  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenixWeb.ApiResponse
  alias KeystonePhoenixWeb.ManagementContract

  @doc "Returns a paginated list of dictionary types."
  def list_types(conn, params) do
    case Dictionary.list_dict_types_all(params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, rows} ->
        json(conn, ApiResponse.ok(Enum.map(rows, &ManagementContract.dictionary_type/1)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @doc "Returns active dictionary items for a select component."
  def list_data_by_type(conn, %{"dict_type" => dict_type} = params) do
    authorization = [authorization: %{principal: conn.assigns.current_user}]

    if paged_request?(params) do
      case Dictionary.list_dict_data_page_by_type(dict_type, params, authorization) do
        {:ok, page} ->
          json(
            conn,
            ApiResponse.ok(%{
              items: Enum.map(page.items, &ManagementContract.dictionary_item/1),
              page: page.page,
              size: page.size,
              total: page.total
            })
          )

        {:error, reason} ->
          render_error(conn, reason)
      end
    else
      case Dictionary.list_dict_data_by_type(dict_type, authorization) do
        {:ok, rows} ->
          json(conn, ApiResponse.ok(Enum.map(rows, &ManagementContract.dictionary_item/1)))

        {:error, reason} ->
          render_error(conn, reason)
      end
    end
  end

  def create_type(conn, params) do
    params = ManagementContract.dictionary_type_params(params)

    case Dictionary.create_dict_type(params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, dict_type} ->
        conn
        |> put_status(:created)
        |> json(
          ApiResponse.ok(
            Dictionary.dict_type_to_map(dict_type)
            |> ManagementContract.dictionary_type()
          )
        )

      {:error, changeset} ->
        render_error(conn, changeset)
    end
  end

  def update_type(conn, %{"code" => code} = params) do
    params =
      params
      |> ManagementContract.dictionary_type_params()
      |> Map.drop(["code", "dictType"])

    case Dictionary.update_dict_type(code, params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, dict_type} ->
        json(
          conn,
          ApiResponse.ok(
            Dictionary.dict_type_to_map(dict_type)
            |> ManagementContract.dictionary_type()
          )
        )

      {:error, :not_found} ->
        render_error(conn, :not_found)

      {:error, changeset} ->
        render_error(conn, changeset)
    end
  end

  def delete_type(conn, %{"code" => code}) do
    case Dictionary.delete_dict_type(code,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      :ok -> json(conn, ApiResponse.ok(%{"deleted" => true}))
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, :has_data} -> render_error(conn, :has_data)
    end
  end

  def create_data(conn, %{"dict_type" => dict_type} = params) do
    params =
      params
      |> Map.put_new("dictType", dict_type)
      |> ManagementContract.dictionary_item_params()

    case Dictionary.create_dict_data(params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, dict_data} ->
        conn
        |> put_status(:created)
        |> json(
          ApiResponse.ok(
            Dictionary.dict_data_to_map(dict_data)
            |> ManagementContract.dictionary_item()
          )
        )

      {:error, changeset} ->
        render_error(conn, changeset)
    end
  end

  def update_data(conn, %{"dict_code" => dict_code} = params) do
    params =
      params
      |> ManagementContract.dictionary_item_params()
      |> Map.drop(["value", "dictValue", "typeCode", "dictType"])

    case Dictionary.update_dict_data(dict_code, params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, dict_data} ->
        json(
          conn,
          ApiResponse.ok(
            Dictionary.dict_data_to_map(dict_data)
            |> ManagementContract.dictionary_item()
          )
        )

      {:error, :not_found} ->
        render_error(conn, :not_found)

      {:error, changeset} ->
        render_error(conn, changeset)
    end
  end

  def delete_data(conn, %{"dict_code" => dict_code}) do
    case Dictionary.delete_dict_data(dict_code,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      :ok -> json(conn, ApiResponse.ok(%{"deleted" => true}))
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(:resource_not_found, "找不到请求的字典数据"))
  end

  defp render_error(conn, :has_data) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "字典类型下存在字典数据，请先删除字典数据"))
  end

  defp render_error(conn, :dict_type_not_found) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "字典类型不存在或已停用"))
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
end
