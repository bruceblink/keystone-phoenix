defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationRoleReload do
  @moduledoc "角色写入后的完整目录和当前页重新读取。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminEvents.OrganizationRolePagination
  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  @doc "先更新完整角色目录，再回到第一页刷新角色列表。"
  def after_success(socket, success, message, extra \\ []) do
    socket = assign(socket, extra)

    case AdminReadSupport.roles(socket) do
      {:ok, rows} ->
        socket
        |> assign(role_rows: rows, role_directory_feedback: nil)
        |> OrganizationRolePagination.refresh(1, success)

      {:error, reason} ->
        feedback = Support.read_error_feedback(reason, message)

        assign(socket, role_feedback: feedback, role_directory_feedback: feedback)
    end
  end
end
