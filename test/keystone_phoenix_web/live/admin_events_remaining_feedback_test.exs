defmodule KeystonePhoenixWeb.Live.AdminEvents.RemainingFeedbackTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Live.AdminEvents.Config
  alias KeystonePhoenixWeb.Live.AdminEvents.Security
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback

  # 直接覆盖入口校验和缺失资源反馈，确保错误码可以用于排错索引。
  test "invalid API key expiry uses a stable validation error code" do
    socket = socket(%{permissions: ["api-key:create"]})

    assert {:noreply, result} =
             Security.handle_event(
               "save-api-key",
               %{"expiresAt" => "invalid"},
               socket
             )

    assert Feedback.code(result.assigns.api_key_feedback) == "api_key_expiry_invalid"

    assert Feedback.message(result.assigns.api_key_feedback) ==
             "API Key 到期时间格式无效，请重新选择时间。"
  end

  test "API Key name and expiry failures map to distinct business codes" do
    name_feedback = Feedback.from_reason(:api_key_name_invalid)
    range_feedback = Feedback.from_reason(:api_key_expiry_out_of_range)

    assert Feedback.code(name_feedback) == "api_key_name_invalid"
    assert Feedback.message(name_feedback) == "API Key 名称必须为 1 到 128 个字符。"
    assert Feedback.code(range_feedback) == "api_key_expiry_out_of_range"

    assert Feedback.message(range_feedback) ==
             "API Key 到期时间必须晚于当前时间且不超过 90 天。"
  end

  test "missing configuration uses a stable resource error code" do
    socket = socket(%{permissions: ["config:update"], config_rows: []})

    assert {:noreply, result} =
             Config.handle_event("edit-config", %{"config-id" => "missing"}, socket)

    assert Feedback.code(result.assigns.config_feedback) == "resource_not_found"
    assert Feedback.message(result.assigns.config_feedback) == "找不到指定配置"
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
