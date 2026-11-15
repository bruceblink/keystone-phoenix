defmodule KeystonePhoenixWeb.Live.AdminEvents.FeedbackCodesTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Live.AdminEvents.Accounts
  alias KeystonePhoenixWeb.Live.AdminEvents.System
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback

  test "missing user edit uses a stable resource error code" do
    socket = socket(%{permissions: ["user:update"], user_rows: []})

    assert {:noreply, result} =
             Accounts.handle_event("edit-user", %{"user-id" => "missing"}, socket)

    assert Feedback.code(result.assigns.user_feedback) == "resource_not_found"
    assert Feedback.message(result.assigns.user_feedback) == "找不到指定用户"
  end

  test "missing dictionary type uses a stable resource error code" do
    socket = socket(%{permissions: ["dictionary:update"], dict_type_rows: []})

    assert {:noreply, result} =
             System.handle_event("edit-dict-type", %{"dict-id" => "missing"}, socket)

    assert Feedback.code(result.assigns.dict_feedback) == "resource_not_found"
    assert Feedback.message(result.assigns.dict_feedback) == "找不到指定字典类型"
  end

  test "missing notice edit uses a stable resource error code" do
    socket = socket(%{permissions: ["notice:update"], notice_rows: []})

    assert {:noreply, result} =
             System.handle_event("edit-notice", %{"notice-id" => "missing"}, socket)

    assert Feedback.code(result.assigns.notice_feedback) == "resource_not_found"
    assert Feedback.message(result.assigns.notice_feedback) == "找不到指定公告"
  end

  test "user import failures expose stable validation and MFA codes" do
    assert Feedback.code(Feedback.import_error(:invalid_workbook)) == "validation_failed"
    assert Feedback.code(Feedback.import_error(:mfa_required)) == "mfa_state_conflict"
  end

  defp socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns:
        Map.merge(
          %{__changed__: %{}, current_user: %{}, permissions: []},
          assigns
        )
    }
  end
end
