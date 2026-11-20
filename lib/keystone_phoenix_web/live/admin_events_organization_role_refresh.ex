defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleRefresh do
  @moduledoc "角色筛选条件更新和第一页刷新。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationRolePagination
  alias KeystonePhoenixWeb.Live.AdminPages.OrganizationFilters
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  @doc "保存角色筛选条件，清理旧选择并读取第一页。"
  def refresh(socket, params) do
    filter =
      OrganizationFilters.organization_filter(params, socket.assigns[:role_filter], [
        "roleKeyword",
        "roleStatus"
      ])

    socket =
      assign(socket,
        role_form: Support.empty_role_form(),
        role_filter: filter,
        active_modal: nil,
        selected_role_ids: [],
        selected_role_id: "",
        selected_role_name: "",
        allocated_role_user_rows: [],
        unallocated_role_user_rows: [],
        role_user_totals: %{allocated: 0, unallocated: 0},
        role_user_feedback: nil
      )

    OrganizationRolePagination.refresh(socket, 1)
  end
end
