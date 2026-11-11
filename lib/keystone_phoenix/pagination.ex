defmodule KeystonePhoenix.Pagination do
  @moduledoc "Shared pagination for Ecto query-backed list endpoints."

  import Ecto.Query

  alias KeystonePhoenix.Repo

  @default_page 1
  @default_page_size 10
  @max_page_size 500

  @doc "Runs a bounded Ecto query and maps each returned row."
  def page(query, params, count_field, mapper) when is_function(mapper, 1) do
    page_rows(query, params, count_field)
    |> Map.update!(:rows, &Enum.map(&1, mapper))
  end

  @doc "Runs a bounded Ecto query and returns raw rows for batch mappers."
  def page_rows(query, params, count_field) do
    page = positive_integer(params["pageNum"] || params[:page_num], @default_page)
    page_size = positive_integer(params["pageSize"] || params[:page_size], @default_page_size)
    page_size = min(page_size, @max_page_size)
    total = Repo.aggregate(query, :count, count_field)

    rows = query |> limit(^page_size) |> offset(^((page - 1) * page_size)) |> Repo.all()
    %{total: total, rows: rows}
  end

  @doc "Paginates an in-memory list with the same page bounds as query lists."
  def page_list(rows, params, default_page_size \\ @default_page_size) when is_list(rows) do
    page = positive_integer(params["pageNum"] || params[:page_num], @default_page)
    page_size = positive_integer(params["pageSize"] || params[:page_size], default_page_size)
    page_size = min(page_size, @max_page_size)
    %{total: length(rows), rows: Enum.slice(rows, (page - 1) * page_size, page_size)}
  end

  defp positive_integer(nil, default), do: default

  defp positive_integer(value, default) do
    case Integer.parse(to_string(value)) do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end
end
