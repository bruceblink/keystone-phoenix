defmodule KeystonePhoenixWeb.NativeContractTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.NativeContract

  test "user DTO only exposes Native fields" do
    dto =
      NativeContract.user(%{
        "userId" => "user-1",
        "username" => "operator",
        "nickname" => "运维员",
        "deptId" => "dept-1",
        "postId" => "post-1",
        "status" => 1,
        "email" => "operator@example.com",
        "phoneNumber" => "13800000000",
        "sex" => 1,
        "avatar" => nil,
        "loginIp" => "127.0.0.1",
        "loginDate" => "2026-11-15T00:00:00Z",
        "remark" => "",
        "roleCodes" => ["ADMIN"],
        "legacyField" => "must not leak"
      })

    assert Map.keys(dto) |> Enum.sort() ==
             ~w(avatar deptId displayName email enabled id loginAt loginIp phoneNumber postId remark roles sex username)

    refute Map.has_key?(dto, "userId")
    refute Map.has_key?(dto, "nickname")
    refute Map.has_key?(dto, "status")
    refute Map.has_key?(dto, "legacyField")
  end

  test "job DTO only exposes Native fields" do
    dto =
      NativeContract.job(%{
        "jobId" => "job-1",
        "jobCode" => "health",
        "jobName" => "健康检查",
        "jobGroup" => "DEFAULT",
        "invokeTarget" => "system:health",
        "jobParams" => "",
        "cronExpression" => "0 */5 * * * *",
        "concurrent" => 1,
        "status" => 1,
        "remark" => "",
        "lastStatus" => nil,
        "lastRunAt" => nil,
        "legacyField" => "must not leak"
      })

    assert Map.keys(dto) |> Enum.sort() ==
             ~w(code concurrent cron enabled group id invokeTarget jobParams lastRunAt lastStatus name remark)

    refute Map.has_key?(dto, "jobId")
    refute Map.has_key?(dto, "jobName")
    refute Map.has_key?(dto, "status")
    refute Map.has_key?(dto, "legacyField")
  end

  test "job pagination preserves Native page metadata" do
    assert NativeContract.pagination_requested?(%{"page" => "2", "size" => "20"})

    page =
      NativeContract.jobs_page(
        %{rows: [%{"jobId" => "job-1", "jobName" => "任务"}], total: 21},
        %{"pageNum" => "2", "pageSize" => "20"}
      )

    assert page.page == 2
    assert page.size == 20
    assert page.total == 21
    assert [%{"id" => "job-1", "name" => "任务"}] = page.items
  end
end
