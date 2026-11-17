defmodule KeystonePhoenixWeb.Live.OrganizationRoleSelectionTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleSelection
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback

  # 失败时，切换角色应清理旧成员，重试当前角色应保留已有数据。
  test "failed role selection retains data only for the same role" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        selected_role_id: "old-role",
        selected_role_name: "旧角色",
        selected_role_ids: ["old-role"],
        allocated_role_user_rows: [%{"userId" => "old-user"}],
        unallocated_role_user_rows: [%{"userId" => "candidate"}],
        role_user_feedback: nil,
        page_nums: %{"role-users-allocated" => 3, "role-users-unallocated" => 2}
      }
    }

    switched =
      OrganizationRoleSelection.role_users_failed(socket, "new-role", "新角色", :service_unavailable)

    assert switched.assigns.selected_role_id == "new-role"
    assert switched.assigns.selected_role_ids == ["old-role"]
    assert switched.assigns.allocated_role_user_rows == []
    assert switched.assigns.unallocated_role_user_rows == []

    assert switched.assigns.page_nums == %{
             "role-users-allocated" => 1,
             "role-users-unallocated" => 1
           }

    assert Feedback.message(switched.assigns.role_user_feedback) == "角色成员读取失败，请重试"

    retried =
      OrganizationRoleSelection.role_users_failed(socket, "old-role", "旧角色", :service_unavailable)

    assert retried.assigns.allocated_role_user_rows == [%{"userId" => "old-user"}]
    assert retried.assigns.unallocated_role_user_rows == [%{"userId" => "candidate"}]
    assert retried.assigns.page_nums == socket.assigns.page_nums
    assert Feedback.message(retried.assigns.role_user_feedback) == "角色成员读取失败，请重试"
  end
end
