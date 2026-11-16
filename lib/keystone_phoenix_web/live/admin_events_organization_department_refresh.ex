defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationDepartmentRefresh do
  @moduledoc "组织结构筛选条件更新和深链接刷新。"

  alias KeystonePhoenixWeb.Live.AdminPages.FilterNavigation
  alias KeystonePhoenixWeb.Live.AdminPages.OrganizationFilters
  alias KeystonePhoenixWeb.Live.AdminPages.Reload
  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  @doc "刷新组织结构并保存命名 URL 状态。"
  def refresh(socket, params) do
    filter =
      OrganizationFilters.organization_filter(params, socket.assigns[:dept_filter], [
        "deptKeyword",
        "deptStatus"
      ])

    socket =
      Reload.refresh(
        socket,
        &AdminReadSupport.departments/1,
        :dept_rows,
        :dept_feedback,
        "部门列表刷新失败，请重试",
        dept_form: Support.empty_dept_form(),
        dept_filter: filter,
        active_modal: nil
      )

    Phoenix.LiveView.push_patch(socket, to: FilterNavigation.path("depts", filter["keyword"]))
  end
end
