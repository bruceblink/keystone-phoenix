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

    assert Feedback.code(result.assigns.api_key_feedback) == "validation_failed"
    assert Feedback.message(result.assigns.api_key_feedback) == "到期时间格式无效"
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
