defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationPosts do
  @moduledoc "岗位列表的分页读取与写入后刷新。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  @doc "按当前筛选条件读取指定岗位页，并在写入后保留列表状态。"
  def refresh(socket, page, success_message \\ nil, extra \\ []) do
    filter = Map.get(socket.assigns, :post_filter, %{"keyword" => "", "status" => "all"})

    params =
      filter
      |> Map.put("pageNum", page)
      |> Map.put("pageSize", get_in(socket.assigns, [:page_sizes, "posts"]) || 20)

    case AdminReadSupport.posts_page(socket, params) do
      {:ok, result} ->
        assign(
          socket,
          Keyword.merge(extra,
            post_rows: result.rows,
            post_total: result.total,
            page_nums: Map.put(socket.assigns.page_nums, "posts", page),
            post_feedback: success_message
          )
        )

      {:error, reason} ->
        assign(
          socket,
          Keyword.merge(
            extra,
            post_feedback:
              Support.read_error_feedback(
                reason,
                failure_message(success_message)
              )
          )
        )
    end
  end

  def after_success(socket, success_message, extra \\ []),
    do: refresh(socket, 1, success_message, extra)

  defp failure_message(nil),
    do: "岗位列表刷新失败，当前保留旧列表。请点击“刷新岗位”重试。"

  defp failure_message(success_message),
    do: "#{success_message}，但列表刷新失败；当前保留旧列表。请点击“刷新岗位”重试。"
end
