defmodule KeystonePhoenixWeb.Live.AdminSupportTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Live.AdminSupport

  test "matches retained permissions and panel requirements" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        current_user: %{},
        permissions: ["department:read", "operation-log:read"]
      }
    }

    assert AdminSupport.permission_socket?(socket, "department:read")
    refute AdminSupport.permission_socket?(socket, "department:create")
    assert AdminSupport.panel_allowed?(socket, "depts")
    assert AdminSupport.panel_allowed?(socket, "logs")
    refute AdminSupport.panel_allowed?(socket, "users")
  end

  test "administrators bypass panel permission checks" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{current_user: %{}, permissions: ["permission:manage"]}
    }

    assert AdminSupport.panel_allowed?(socket, "users")
    assert AdminSupport.admin_socket?(socket)
  end
end
