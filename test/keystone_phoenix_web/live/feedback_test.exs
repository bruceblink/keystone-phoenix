defmodule KeystonePhoenixWeb.Live.FeedbackTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminSupport

  test "feedback keeps a stable code while preserving rendered message helpers" do
    feedback = AdminSupport.form_error({:error, :not_found})

    assert feedback == {:error, :resource_not_found, "记录不存在"}
    assert Feedback.code(feedback) == :resource_not_found
    assert Feedback.message(feedback) == "记录不存在"
    assert Feedback.class(feedback) == "feedback feedback--error"
    assert Feedback.role(feedback) == "alert"
    assert Feedback.live(feedback) == "assertive"
  end

  test "form errors map authorization, MFA, validation, and service failures" do
    assert Feedback.code(AdminSupport.form_error({:error, :permission_denied})) ==
             :permission_denied

    assert Feedback.code(AdminSupport.form_error({:error, :mfa_enrollment_required})) ==
             :mfa_state_conflict

    assert Feedback.code(AdminSupport.form_error({:error, :invalid_params})) ==
             :validation_failed

    assert Feedback.code(AdminSupport.form_error({:error, :unavailable})) ==
             :service_unavailable
  end

  test "unknown reasons use a stable internal code and safe message" do
    feedback = AdminSupport.form_error({:error, :secret_internal_reason})

    assert feedback == {:error, :internal_error, "操作失败"}
    refute Feedback.message(feedback) =~ "secret_internal_reason"
  end

  test "changeset failures use validation_failed" do
    changeset = Ecto.Changeset.cast({%{}, %{}}, %{}, [])

    assert Feedback.code(AdminSupport.form_error({:error, changeset})) == :validation_failed
  end
end
