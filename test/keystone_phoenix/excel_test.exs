defmodule KeystonePhoenix.ExcelTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Excel

  test "exports and imports an xlsx worksheet" do
    path =
      Path.join(System.tmp_dir!(), "keystone-excel-#{System.unique_integer([:positive])}.xlsx")

    on_exit(fn -> File.rm(path) end)

    assert {:ok, binary} = Excel.export(["用户名", "状态"], [["alice", 1]], "users.xlsx")
    assert byte_size(binary) > 100
    assert :ok = File.write(path, binary)
    assert {:ok, [["用户名", "状态"], ["alice", 1]]} = Excel.import_rows(path)

    assert {:ok, [%{"username" => "alice", "status" => 1}]} =
             Excel.rows_to_maps([["用户名", "状态"], ["alice", 1]])
  end

  test "fetches every page for an export" do
    fetcher = fn %{"pageNum" => page, "pageSize" => 500} ->
      rows = if page == 1, do: [%{id: 1}, %{id: 2}], else: [%{id: 3}]
      %{total: 3, rows: rows}
    end

    assert [%{id: 1}, %{id: 2}, %{id: 3}] = Excel.all_rows(fetcher)
  end

  test "rejects an invalid workbook path and malformed headers" do
    assert {:error, :invalid_workbook} = Excel.import_rows("/tmp/missing.xls")
    assert {:error, :empty_sheet} = Excel.rows_to_maps([])
    assert {:error, :invalid_headers} = Excel.rows_to_maps([["用户名", ""], ["alice", 1]])
    assert {:error, :invalid_headers} = Excel.rows_to_maps([["用户名", "未知列"], ["alice", 1]])
    assert {:error, :invalid_headers} = Excel.rows_to_maps([["用户名", "用户名"], ["alice", "bob"]])
  end
end
