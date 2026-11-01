defmodule KeystonePhoenix.Dictionary do
  @moduledoc """
  Query boundary for the PostgreSQL-backed Keystone dictionary tables.
  """

  import Ecto.Query

  alias KeystonePhoenix.Dictionary.{DictData, DictType}
  alias KeystonePhoenix.Repo

  @default_page 1
  @default_page_size 10
  @max_page_size 500

  @spec list_dict_types(map()) :: %{rows: list(), total: non_neg_integer()}
  def list_dict_types(params \\ %{}) do
    query =
      from d in DictType,
        where: d.deleted == false,
        order_by: [desc: d.dict_id]

    query =
      query
      |> filter_contains(:dict_name, params["dictName"] || params[:dict_name])
      |> filter_contains(:dict_type, params["dictType"] || params[:dict_type])
      |> filter_status(params["status"] || params[:status])

    page_query(query, params, :dict_id, &dict_type_to_map/1)
  end

  @spec list_dict_data(map()) :: %{rows: list(), total: non_neg_integer()}
  def list_dict_data(params \\ %{}) do
    query =
      from d in DictData,
        where: d.deleted == false,
        order_by: [asc: d.dict_sort, asc: d.dict_code]

    query =
      query
      |> filter_equal(:dict_type, params["dictType"] || params[:dict_type])
      |> filter_contains(:dict_label, params["dictLabel"] || params[:dict_label])
      |> filter_status(params["status"] || params[:status])

    page_query(query, params, :dict_code, &dict_data_to_map/1)
  end

  @spec list_dict_data_by_type(String.t()) :: [map()]
  def list_dict_data_by_type(dict_type) when is_binary(dict_type) do
    from(d in DictData,
      where: d.deleted == false and d.status == 1 and d.dict_type == ^dict_type,
      order_by: [asc: d.dict_sort, asc: d.dict_code]
    )
    |> Repo.all()
    |> Enum.map(&dict_data_to_map/1)
  end

  defp page_query(query, params, count_field, mapper) do
    page = positive_integer(params["pageNum"] || params[:page_num], @default_page)
    page_size = positive_integer(params["pageSize"] || params[:page_size], @default_page_size)
    page_size = min(page_size, @max_page_size)

    total = Repo.aggregate(query, :count, count_field)
    query = query |> limit(^page_size) |> offset(^((page - 1) * page_size))

    rows = Repo.all(query)

    %{total: total, rows: Enum.map(rows, mapper)}
  end

  defp filter_contains(query, _field, nil), do: query
  defp filter_contains(query, _field, ""), do: query

  defp filter_contains(query, field, value) do
    value = "%#{String.trim(to_string(value))}%"
    where(query, [record], ilike(field(record, ^field), ^value))
  end

  defp filter_equal(query, _field, nil), do: query
  defp filter_equal(query, _field, ""), do: query

  defp filter_equal(query, field, value) do
    where(query, [record], field(record, ^field) == ^value)
  end

  defp filter_status(query, nil), do: query
  defp filter_status(query, ""), do: query

  defp filter_status(query, value) do
    case Integer.parse(to_string(value)) do
      {status, ""} -> where(query, [record], record.status == ^status)
      _ -> query
    end
  end

  defp positive_integer(nil, default), do: default

  defp positive_integer(value, default) do
    case Integer.parse(to_string(value)) do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end

  defp dict_type_to_map(dict_type) do
    %{
      "dictId" => dict_type.dict_id,
      "dictName" => dict_type.dict_name,
      "dictType" => dict_type.dict_type,
      "status" => dict_type.status,
      "remark" => dict_type.remark,
      "createTime" => format_datetime(dict_type.create_time)
    }
  end

  defp dict_data_to_map(dict_data) do
    %{
      "dictCode" => dict_data.dict_code,
      "dictType" => dict_data.dict_type,
      "dictLabel" => dict_data.dict_label,
      "dictValue" => dict_data.dict_value,
      "dictSort" => dict_data.dict_sort,
      "isDefault" => dict_data.is_default,
      "cssClass" => dict_data.css_class,
      "listClass" => dict_data.list_class,
      "status" => dict_data.status,
      "remark" => dict_data.remark,
      "createTime" => format_datetime(dict_data.create_time)
    }
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
