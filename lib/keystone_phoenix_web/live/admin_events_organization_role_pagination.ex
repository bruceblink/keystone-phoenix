defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationRolePagination do
  @moduledoc "角色列表服务端分页的读取事件。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  @doc "按当前筛选条件读取角色当前页，并写入总数量。"
  def refresh(socket, page) do
    filter = Map.get(socket.assigns, :role_filter, %{"keyword" => "", "status" => "all"})

    params =
      filter
      |> Map.put("pageNum", page)
      |> Map.put("pageSize", get_in(socket.assigns, [:page_sizes, "roles"]) || 20)

    case AdminReadSupport.roles_page(socket, params) do
      {:ok, result} ->
        assign(socket,
          role_page_rows: result.rows,
          role_total: result.total,
          page_nums: Map.put(socket.assigns.page_nums, "roles", page),
          role_feedback: nil
        )

      {:error, reason} ->
        assign(socket, role_feedback: Support.read_error_feedback(reason, "角色列表刷新失败，请重试"))
    end
  end
end
