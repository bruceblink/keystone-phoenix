defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationDeepLinks do
  @moduledoc "登录后恢复菜单和组织结构的深链接筛选条件。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  @doc "重新读取完整菜单树；失败时清空旧数据并显示安全错误。"
  def restore_menus_from_deep_link(socket) do
    case AdminReadSupport.menus(socket) do
      {:ok, rows} ->
        {:noreply, assign(socket, menu_rows: rows, menu_feedback: nil)}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           menu_rows: [],
           menu_feedback: Support.read_error_feedback(reason, "菜单列表读取失败，请重试")
         )}
    end
  end

  @doc "重新读取完整部门树；失败时清空旧数据并显示安全错误。"
  def restore_departments_from_deep_link(socket) do
    case AdminReadSupport.departments(socket) do
      {:ok, rows} ->
        {:noreply, assign(socket, dept_rows: rows, dept_feedback: nil)}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           dept_rows: [],
           dept_feedback: Support.read_error_feedback(reason, "部门列表读取失败，请重试")
         )}
    end
  end
end
