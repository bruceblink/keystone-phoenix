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
end
