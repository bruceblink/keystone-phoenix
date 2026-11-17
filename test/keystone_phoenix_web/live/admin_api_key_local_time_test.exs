defmodule KeystonePhoenixWeb.AdminApiKeyLocalTimeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.ApiKeys

  test "API Key timestamps use the browser local-time hook" do
    created_at = ~U[2026-11-17 19:27:23Z]

    html =
      render_component(&ApiKeys.api_keys/1, %{
        api_key_rows: [
          %{
            id: "00000000-0000-7000-8000-000000000001",
            name: "test key",
            prefix: "testprefix",
            scopes: [],
            created_at: created_at,
            last_used_at: nil,
            expires_at: nil,
            revoked_at: nil
          }
        ],
        api_key_total: 1,
        permissions: [],
        read_only: true,
        active_modal: nil
      })

    assert html =~ ~s(phx-hook="LocalDateTime")
    assert html =~ ~s(data-utc-time="2026-11-17T19:27:23Z")
    assert html =~ "从未使用"
    assert html =~ "永不过期"
  end
end
