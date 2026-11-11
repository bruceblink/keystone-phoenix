defmodule KeystonePhoenixWeb.PaginationTest do
  use KeystonePhoenixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.Pagination

  test "renders accessible controls for multiple pages" do
    html =
      render_component(&Pagination.pagination/1, %{
        panel: "users",
        page_num: 2,
        page_size: 50,
        total: 120
      })

    assert html =~ ~s(aria-label="分页")
    assert html =~ ~s(phx-value-page="1")
    assert html =~ ~s(phx-value-page="3")
    assert html =~ "第 2 / 3 页，共 120 条"
  end

  test "hides controls when all rows fit one page" do
    html =
      render_component(&Pagination.pagination/1, %{
        panel: "users",
        page_num: 1,
        page_size: 50,
        total: 50
      })

    refute html =~ "分页"
  end

  test "slices loaded rows with safe page defaults" do
    assert Pagination.page_rows(Enum.to_list(1..120), 2, 50) == Enum.to_list(51..100)
    assert Pagination.page_rows([:only], 0, 0) == [:only]
    assert Pagination.page_rows(:invalid, 1, 50) == []
  end
end
