defmodule KeystonePhoenixWeb.OperationAuditRenderTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.System

  test "操作审计行复用 Native 字段映射并为缺失值显示占位符" do
    # 用真实 DTO 适配器输入核验页面字段，不在测试中复制映射逻辑。
    html =
      render_component(&System.logs/1, %{
        kind: "operation",
        login_log_rows: [],
        operation_log_rows: [
          %{
            "operationId" => "audit-update",
            "businessTypeStr" => "修改",
            "requestMethod" => "POST",
            "requestModule" => "user",
            "userId" => "target-user-id",
            "resourceId" => "legacy-resource-id",
            "operationResult" => "用户资料已更新",
            "operationParam" => "请求参数",
            "operationTime" => "2026-11-18 10:30:00",
            "username" => "operator",
            "requestUrl" => "/legacy-resource-url",
            "status" => 1
          },
          %{"operationId" => "audit-missing"}
        ],
        operation_log_total: 2,
        log_feedback: nil
      })

    [table_body] = Regex.run(~r/<tbody>(.*?)<\/tbody>/s, html, capture: :all_but_first)

    rows =
      Regex.scan(~r/<tr>(.*?)<\/tr>/s, table_body, capture: :all_but_first) |> Enum.map(&hd/1)

    [mapped_row, missing_row] = rows

    assert mapped_row =~ ~s(<td class="audit-time">2026-11-18 10:30:00</td>)
    assert mapped_row =~ ~s(<td class="audit-actor">operator</td>)
    assert mapped_row =~ ~s(<span class="badge badge-neutral">修改</span>)
    assert mapped_row =~ ~s(<td class="audit-resource">user</td>)
    assert mapped_row =~ ~s(<td class="audit-resource-id">target-user-id</td>)
    assert mapped_row =~ ~s(<td class="audit-detail">用户资料已更新</td>)
    refute mapped_row =~ "POST"
    refute mapped_row =~ "legacy-resource"

    assert missing_row =~ ~s(<td class="audit-time">—</td>)
    assert missing_row =~ ~s(<td class="audit-actor">—</td>)
    assert missing_row =~ ~s(<span class="badge badge-neutral">—</span>)
    assert missing_row =~ ~s(<td class="audit-resource">—</td>)
    assert missing_row =~ ~s(<td class="audit-resource-id">—</td>)
    assert missing_row =~ ~s(<td class="audit-detail">—</td>)
  end
end
