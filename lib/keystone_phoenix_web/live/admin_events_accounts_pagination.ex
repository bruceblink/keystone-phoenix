defmodule KeystonePhoenixWeb.Live.AdminEvents.AccountsPagination do
  @moduledoc "用户列表服务端分页和写入后重新读取。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  @doc "读取用户当前页，保留筛选条件并清空跨页选择。"
  def paginate(params, socket) do
    with {page, ""} when page > 0 <- Integer.parse(to_string(params["page"])),
         {:ok, result} <- load(socket, user_filters(socket), page) do
      {:noreply,
       assign(socket,
         user_rows: result.rows,
         user_total: result.total,
         users_server_paged: true,
         page_nums: Map.put(socket.assigns.page_nums, "users", result.page),
         user_feedback: nil,
         selected_user_ids: []
       )}
    else
      {:error, reason} ->
        {:noreply,
         assign(socket, user_feedback: Support.read_error_feedback(reason, "用户列表翻页失败，请重试"))}

      _ ->
        {:noreply, socket}
    end
  end

  @doc "按当前页重新读取用户，失败时保留旧列表并显示业务错误。"
  def assign_reloaded(socket, extra) do
    case load(socket, user_filters(socket), current_page(socket)) do
      {:ok, page} ->
        assign(
          socket,
          Map.merge(Map.new(extra), %{
            user_rows: page.rows,
            user_total: page.total,
            users_server_paged: true
          })
        )

      {:error, reason} ->
        assign(socket, user_feedback: Support.read_error_feedback(reason, "用户列表刷新失败，请重试"))
    end
  end

  def page_params(socket, page),
    do: %{"pageNum" => page, "pageSize" => get_in(socket.assigns, [:page_sizes, "users"]) || 20}

  def user_filters(socket) do
    %{
      "username" => String.trim(to_string(socket.assigns[:user_query] || "")),
      "displayName" => String.trim(to_string(socket.assigns[:user_display_name_query] || ""))
    }
  end

  defp load(socket, filters, page) do
    Support.load_users_for_socket_result(socket, Map.merge(filters, page_params(socket, page)))
  end

  defp current_page(socket), do: get_in(socket.assigns, [:page_nums, "users"]) || 1
end
