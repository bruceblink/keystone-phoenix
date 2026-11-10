defmodule KeystonePhoenix.Excel do
  @moduledoc "Excel export/import helpers shared by the administrative endpoints."

  @max_file_size 50 * 1024 * 1024
  @page_size 500
  @required_headers ~w(username)

  @header_aliases %{
    "部门ID" => "deptId",
    "部门 Id" => "deptId",
    "deptId" => "deptId",
    "用户名" => "username",
    "username" => "username",
    "昵称" => "nickname",
    "用户昵称" => "nickname",
    "nickname" => "nickname",
    "邮件" => "email",
    "邮箱" => "email",
    "email" => "email",
    "电话号码" => "phoneNumber",
    "号码" => "phoneNumber",
    "phoneNumber" => "phoneNumber",
    "性别" => "sex",
    "sex" => "sex",
    "头像" => "avatar",
    "avatar" => "avatar",
    "密码" => "password",
    "password" => "password",
    "状态" => "status",
    "status" => "status",
    "角色ID" => "roleId",
    "roleId" => "roleId",
    "职位ID" => "postId",
    "postId" => "postId",
    "备注" => "remark",
    "remark" => "remark"
  }

  @doc "Builds an XLSX workbook in memory from a header row and data rows."
  @spec export([term()], [[term()]], String.t()) :: {:ok, binary()} | {:error, term()}
  def export(headers, rows, filename) when is_list(headers) and is_list(rows) do
    sheet = %Elixlsx.Sheet{
      name: "Sheet1",
      rows: [headers | rows] |> Enum.map(&normalize_export_row/1)
    }

    workbook = Elixlsx.Workbook.append_sheet(%Elixlsx.Workbook{}, sheet)

    case Elixlsx.write_to_memory(workbook, filename) do
      {:ok, {_generated_name, binary}} -> {:ok, binary}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, {:write_failed, error}}
  end

  @doc "Reads the first worksheet from a local XLSX file."
  @spec import_rows(String.t()) :: {:ok, [[term()]]} | {:error, atom()}
  def import_rows(path) when is_binary(path) do
    import_rows(path, Path.basename(path))
  end

  def import_rows(_path), do: {:error, :invalid_workbook}

  @doc "Reads a multipart XLSX path using the client-provided filename for type validation."
  @spec import_rows(String.t(), String.t()) :: {:ok, [[term()]]} | {:error, atom()}
  def import_rows(path, filename) when is_binary(path) and is_binary(filename) do
    with :ok <- validate_import_file(path, filename),
         {:ok, table_id} <- extract(path) do
      try do
        {:ok, Xlsxir.get_list(table_id)}
      after
        Xlsxir.close(table_id)
      end
    end
  rescue
    _error -> {:error, :invalid_workbook}
  end

  def import_rows(_path, _filename), do: {:error, :invalid_workbook}

  @doc "Converts a worksheet with a header row into maps using API field names."
  @spec rows_to_maps([[term()]]) :: {:ok, [map()]} | {:error, atom()}
  def rows_to_maps([headers | rows]) when is_list(headers) do
    headers = Enum.map(headers, &canonical_header/1)

    cond do
      headers == [] or Enum.any?(headers, &(&1 == "")) ->
        {:error, :invalid_headers}

      Enum.any?(
        headers,
        &(!Map.has_key?(@header_aliases, &1) and &1 not in Map.values(@header_aliases))
      ) ->
        {:error, :invalid_headers}

      length(headers) != length(Enum.uniq(headers)) ->
        {:error, :invalid_headers}

      Enum.any?(@required_headers, &(&1 not in headers)) ->
        {:error, :invalid_headers}

      true ->
        {:ok,
         rows
         |> Enum.reject(&blank_row?/1)
         |> Enum.map(&row_to_map(&1, headers))}
    end
  end

  def rows_to_maps(_rows), do: {:error, :empty_sheet}

  @doc "Fetches all pages from a paginated query for an export operation."
  @spec all_rows((map() -> map()), map()) :: [map()]
  def all_rows(fetcher, params \\ %{}) when is_function(fetcher, 1) and is_map(params) do
    do_all_rows(fetcher, params, 1, [], @page_size)
  end

  @doc "Returns the canonical API key for an Excel header."
  @spec canonical_header(term()) :: String.t()
  def canonical_header(header) do
    header = cell_to_string(header) |> String.trim()
    Map.get(@header_aliases, header, header)
  end

  @doc "Converts a worksheet value into a safe API value."
  @spec import_value(term()) :: term()
  def import_value(nil), do: nil
  def import_value(value) when is_binary(value), do: String.trim(value)
  def import_value(value) when is_integer(value), do: value

  def import_value(value) when is_float(value) do
    if value == trunc(value), do: trunc(value), else: value
  end

  def import_value({year, month, day}) when is_integer(year) do
    Calendar.strftime(Date.new!(year, month, day), "%Y-%m-%d")
  end

  def import_value(value), do: cell_to_string(value)

  defp extract(path) do
    case Xlsxir.extract(path, 0) do
      {:ok, table_id} -> {:ok, table_id}
      {:error, _reason} -> {:error, :invalid_workbook}
      _other -> {:error, :invalid_workbook}
    end
  end

  defp validate_import_file(path, filename) do
    extension = filename |> Path.extname() |> String.downcase()

    with true <- extension == ".xlsx",
         {:ok, stat} <- File.stat(path),
         true <- stat.size > 0 and stat.size <= @max_file_size do
      :ok
    else
      false -> {:error, :invalid_workbook}
      {:error, _reason} -> {:error, :invalid_workbook}
    end
  end

  defp normalize_export_row(row), do: Enum.map(row, &export_value/1)

  defp export_value(nil), do: ""
  defp export_value(value) when is_binary(value), do: value
  defp export_value(value) when is_integer(value) or is_float(value), do: value
  defp export_value(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S")

  defp export_value(%NaiveDateTime{} = value),
    do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S")

  defp export_value(%Date{} = value), do: Calendar.strftime(value, "%Y-%m-%d")
  defp export_value(value) when is_atom(value), do: Atom.to_string(value)
  defp export_value(value) when is_list(value), do: Enum.map_join(value, ",", &to_string/1)
  defp export_value(value), do: inspect(value)

  defp row_to_map(row, headers) do
    headers
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {header, index}, result ->
      Map.put(result, header, import_value(Enum.at(row, index)))
    end)
  end

  defp blank_row?(row) do
    Enum.all?(row, fn value ->
      case import_value(value) do
        nil -> true
        value when is_binary(value) -> value == ""
        _value -> false
      end
    end)
  end

  defp do_all_rows(fetcher, params, page, groups, page_size) do
    result = fetcher.(Map.merge(params, %{"pageNum" => page, "pageSize" => page_size}))
    rows = Map.get(result, :rows, Map.get(result, "rows", []))
    total = Map.get(result, :total, Map.get(result, "total", 0))
    groups = [Enum.reverse(rows) | groups]
    loaded = groups |> List.flatten() |> length()

    if rows == [] or loaded >= total do
      groups |> List.flatten() |> Enum.reverse()
    else
      do_all_rows(fetcher, params, page + 1, groups, page_size)
    end
  end

  defp cell_to_string(value) when is_binary(value), do: value
  defp cell_to_string(nil), do: ""
  defp cell_to_string(value), do: to_string(value)
end
