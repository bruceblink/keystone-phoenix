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

  test "preserves task read failures for LiveView feedback" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, current_user: %{}, permissions: []}
    }

    assert {:error, :permission_denied} = AdminSupport.load_jobs_for_socket_result(socket)

    feedback = AdminSupport.read_error_feedback(:permission_denied, "任务列表读取失败，请重试")
    assert KeystonePhoenixWeb.Live.AdminPages.Feedback.code(feedback) == "permission_denied"
    assert KeystonePhoenixWeb.Live.AdminPages.Feedback.message(feedback) == "任务列表读取失败，请重试"
  end

  test "preserves system panel read failures for LiveView feedback" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, current_user: %{}, permissions: []}
    }

    assert {:error, :permission_denied} = AdminSupport.load_notices_for_socket_result(socket)

    assert {:error, :permission_denied} =
             AdminSupport.load_dict_data_for_socket_result(socket, "system_status")

    assert {:error, :permission_denied} =
             AdminSupport.load_dictionary_for_socket_result(socket, "")
  end
end
