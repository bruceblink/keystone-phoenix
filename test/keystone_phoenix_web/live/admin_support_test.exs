defmodule KeystonePhoenixWeb.Live.AdminSupportTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Live.AdminSupport

  test "matches retained permissions and panel requirements" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        current_user: %{"isAdmin" => 0},
        permissions: ["system:dept:list", "monitor:operlog:list"]
      }
    }

    assert AdminSupport.permission_socket?(socket, "system:dept:list")
    refute AdminSupport.permission_socket?(socket, "system:dept:add")
    assert AdminSupport.panel_allowed?(socket, "depts")
    assert AdminSupport.panel_allowed?(socket, "logs")
    refute AdminSupport.panel_allowed?(socket, "users")
  end

  test "administrators bypass panel permission checks" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{current_user: %{"isAdmin" => 1}, permissions: []}
    }

    assert AdminSupport.panel_allowed?(socket, "users")
    assert AdminSupport.permission_socket?(socket, "system:user:remove")
  end
end
