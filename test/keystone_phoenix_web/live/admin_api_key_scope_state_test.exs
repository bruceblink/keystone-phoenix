defmodule KeystonePhoenixWeb.AdminApiKeyScopeStateTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Live.AdminEvents.Security

  test "a stale form change does not clear a scope selected by the preceding event" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        permissions: ["user:read"],
        api_key_form: %{"name" => "test key", "expiresAt" => "", "scopes" => ""},
        api_key_scope_query: ""
      }
    }

    {:noreply, selected} =
      Security.handle_event(
        "toggle-api-key-scope",
        %{"scope" => "user:read", "selected" => "true"},
        socket
      )

    assert selected.assigns.api_key_form["scopes"] == "user:read"

    # 模拟网络中较晚到达、仍带旧 hidden scopes 的表单变更事件。
    {:noreply, filtered} =
      Security.handle_event(
        "filter-api-key-scopes",
        %{
          "name" => "test key",
          "expiresAt" => "",
          "scopes" => "",
          "scopeQuery" => "user"
        },
        selected
      )

    assert filtered.assigns.api_key_form["scopes"] == "user:read"
    assert filtered.assigns.api_key_scope_query == "user"
  end
end
