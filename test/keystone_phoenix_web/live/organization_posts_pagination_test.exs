defmodule KeystonePhoenixWeb.Live.OrganizationPostsPaginationTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.Organization

  # 岗位列表保持 admin-web 的每页 20 条，并使用共享 LiveView 分页控件。
  test "岗位列表按页展示并提供分页状态" do
    rows =
      for id <- 1..21 do
        %{
          "postId" => id,
          "postCode" => "post-#{id}",
          "postName" => "岗位 #{id}",
          "postSort" => id,
          "status" => 1
        }
      end

    html =
      render_component(&Organization.posts/1,
        post_rows: [List.last(rows)],
        post_total: length(rows),
        post_form: %{},
        post_feedback: nil,
        active_modal: nil,
        page_num: 2,
        page_size: 20,
        read_only: true,
        permissions: []
      )

    assert html =~ "岗位 21"
    refute html =~ "岗位 1"
    assert html =~ "第 2 / 2 页，共 21 条"
    assert html =~ ~s(phx-value-panel="posts")
  end
end
