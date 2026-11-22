defmodule KeystonePhoenixWeb.Live.FeedbackTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminSupport
  alias KeystonePhoenixWeb.ErrorCatalog
  alias KeystonePhoenix.Notice.SysNotice

  test "feedback keeps a stable code while preserving rendered message helpers" do
    feedback = AdminSupport.form_error({:error, :not_found})

    assert feedback == {:error, "resource_not_found", "记录不存在"}
    assert Feedback.code(feedback) == "resource_not_found"
    assert Feedback.message(feedback) == "记录不存在"
    assert Feedback.class(feedback) == "feedback feedback--error"
    assert Feedback.role(feedback) == "alert"
    assert Feedback.live(feedback) == "assertive"
  end

  test "form errors map authorization, MFA, validation, and service failures" do
    assert Feedback.code(AdminSupport.form_error({:error, :permission_denied})) ==
             "permission_denied"

    assert Feedback.code(AdminSupport.form_error({:error, :mfa_enrollment_required})) ==
             "mfa_state_conflict"

    assert Feedback.code(AdminSupport.form_error({:error, :invalid_params})) ==
             "validation_failed"

    assert Feedback.code(AdminSupport.form_error({:error, :unavailable})) ==
             "service_unavailable"
  end

  test "role deletion errors distinguish members from protected roles" do
    assert Feedback.code(Feedback.role_delete_error(:has_users)) == "role_has_members"
    assert Feedback.code(Feedback.role_delete_error(:protected_role)) == "role_protected"

    # 部门和其他页面仍通过通用映射使用 resource_conflict。
    assert Feedback.code(Feedback.from_reason(:has_users)) == "resource_conflict"
  end

  test "API Key pagination changes use a unique retryable diagnostic code" do
    # 验证分页变化通过目录登记的专用代码反馈，并允许调用方重试。
    feedback = Feedback.error(:api_key_page_changed, "列表在读取期间多次变化，请刷新后重试")

    assert Feedback.code(feedback) == "api_key_page_changed"

    assert ErrorCatalog.lookup(:api_key_page_changed) == %{
             code: "api_key_page_changed",
             status: 409,
             retryable: true,
             message_key: "error.api_key_page_changed"
           }
  end

  test "unknown reasons use a stable internal code and safe message" do
    feedback = AdminSupport.form_error({:error, :secret_internal_reason})

    assert feedback == {:error, "internal_error", "操作失败"}
    refute Feedback.message(feedback) =~ "secret_internal_reason"
  end

  test "changeset failures use validation_failed" do
    changeset = Ecto.Changeset.cast({%{}, %{}}, %{}, [])

    assert Feedback.code(AdminSupport.form_error({:error, changeset})) == "validation_failed"
  end

  test "notice type length changeset keeps its dedicated error code" do
    changeset =
      SysNotice.changeset(%SysNotice{}, %{
        notice_title: "title",
        notice_content: "content",
        notice_type: String.duplicate("x", 33),
        status: 1
      })

    assert Feedback.code(AdminSupport.form_error({:error, changeset})) == "notice_type_invalid"
  end
end
