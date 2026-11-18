defmodule KeystonePhoenixWeb.Live.AdminEvents.Notices do
  @moduledoc "LiveView event handlers for paged notice management."

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Notice
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def handle_event("refresh-notices", _params, socket) do
    if Support.panel_allowed?(socket, "notices"),
      do:
        reload_notice_page(socket, current_page(socket), nil,
          selected_notice_ids: [],
          active_modal: nil
        ),
      else: {:noreply, socket}
  end

  def handle_event("filter-notices", params, socket) do
    if Support.panel_allowed?(socket, "notices") do
      socket =
        assign(socket,
          selected_notice_ids: [],
          notice_filter: %{
            "title" => String.trim(params["noticeTitle"] || ""),
            "published" => params["published"] || "all"
          }
        )

      reload_notice_page(socket, 1, nil)
    else
      {:noreply, socket}
    end
  end

  def handle_event("reset-notice-filter", _params, socket) do
    if Support.panel_allowed?(socket, "notices") do
      socket =
        assign(socket,
          selected_notice_ids: [],
          notice_filter: %{"title" => "", "published" => "all"}
        )

      reload_notice_page(socket, 1, nil)
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-notice", %{"notice-id" => notice_id}, socket) do
    if Support.permission_socket?(socket, "notice:update") do
      case Enum.find(socket.assigns.notice_rows, &(to_string(&1["noticeId"]) == notice_id)) do
        nil ->
          {:noreply,
           assign(socket, notice_feedback: Feedback.error(:resource_not_found, "找不到指定公告"))}

        notice ->
          {:noreply,
           assign(socket, notice_form: notice, notice_feedback: nil, active_modal: "notice")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-notice", _params, socket) do
    if Support.permission_socket?(socket, "notice:create") do
      {:noreply,
       assign(socket,
         notice_form: Support.empty_notice_form(),
         notice_feedback: nil,
         active_modal: "notice"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel-notice", _params, socket) do
    if Support.permission_socket?(socket, "notice:update") do
      {:noreply,
       assign(socket,
         notice_form: Support.empty_notice_form(),
         notice_feedback: nil,
         active_modal: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-notice", params, socket) do
    if Support.permission_socket?(socket, "notice:create") or
         Support.permission_socket?(socket, "notice:update") do
      notice_id = String.trim(params["noticeId"] || "")

      result =
        if notice_id == "",
          do: Notice.create_notice(params, authorization: self_authorization(socket)),
          else: Notice.update_notice(notice_id, params, authorization: self_authorization(socket))

      case result do
        {:ok, _notice} ->
          reload_notice_page(socket, 1, if(notice_id == "", do: "公告已创建", else: "公告已更新"),
            selected_notice_ids: [],
            notice_form: Support.empty_notice_form(),
            active_modal: nil
          )

        {:error, changeset} ->
          {:noreply, assign(socket, notice_feedback: Support.form_error(changeset))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "toggle-notice-status",
        %{"notice-id" => notice_id, "status" => status},
        socket
      ) do
    if Support.permission_socket?(socket, "notice:update") do
      case Notice.update_notice(notice_id, %{"status" => status},
             authorization: self_authorization(socket)
           ) do
        {:ok, _notice} ->
          reload_notice_page(socket, 1, "公告状态已更新", selected_notice_ids: [])

        {:error, :not_found} ->
          {:noreply,
           assign(socket, notice_feedback: Feedback.error(:resource_not_found, "找不到指定公告"))}

        {:error, changeset} ->
          {:noreply, assign(socket, notice_feedback: Support.form_error(changeset))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "publish-notice",
        %{"notice-id" => notice_id, "published" => published},
        socket
      ) do
    if Support.permission_socket?(socket, "notice:update") do
      case Notice.publish_notice(notice_id, published == "true",
             authorization: self_authorization(socket)
           ) do
        {:ok, _notice} ->
          message = if published == "true", do: "公告已发布", else: "公告已取消发布"
          reload_notice_page(socket, 1, message, selected_notice_ids: [])

        {:error, :not_found} ->
          {:noreply,
           assign(socket, notice_feedback: Feedback.error(:resource_not_found, "找不到指定公告"))}

        {:error, changeset} ->
          {:noreply, assign(socket, notice_feedback: Support.form_error(changeset))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "toggle-notice-selection",
        %{"notice-id" => notice_id, "selected" => selected},
        socket
      ) do
    ids = Map.get(socket.assigns, :selected_notice_ids, [])

    ids =
      if selected == "true", do: Enum.uniq([notice_id | ids]), else: List.delete(ids, notice_id)

    {:noreply, assign(socket, selected_notice_ids: ids)}
  end

  def handle_event("toggle-all-notice-selection", %{"selected" => selected}, socket) do
    page_ids = Enum.map(socket.assigns.notice_rows, &to_string(&1["noticeId"]))
    ids = Map.get(socket.assigns, :selected_notice_ids, [])
    ids = if selected == "true", do: Enum.uniq(ids ++ page_ids), else: ids -- page_ids
    {:noreply, assign(socket, selected_notice_ids: ids)}
  end

  def handle_event("paginate-notices", %{"page" => page}, socket) do
    case Integer.parse(to_string(page)) do
      {page, ""} when page > 0 -> reload_notice_page(socket, page, nil)
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete-notices", %{"notice-ids" => ids}, socket) do
    if Support.permission_socket?(socket, "notice:delete") do
      case Notice.delete_notices(String.split(ids || "", ",", trim: true),
             authorization: self_authorization(socket)
           ) do
        :ok ->
          reload_notice_page(socket, 1, "公告已删除", selected_notice_ids: [], active_modal: nil)

        {:error, :not_found} ->
          {:noreply,
           assign(socket, notice_feedback: Feedback.error(:resource_not_found, "找不到指定公告"))}

        {:error, :invalid_ids} ->
          {:noreply,
           assign(socket, notice_feedback: Feedback.error(:validation_failed, "公告编号无效"))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-notice", %{"notice-id" => notice_id}, socket),
    do: handle_event("delete-notices", %{"notice-ids" => notice_id}, socket)

  defp reload_notice_page(socket, page, success, extra \\ []) do
    case load_notice_page(socket, page) do
      {:ok, result} ->
        attrs = [
          notice_rows: result.items,
          notice_total: result.total,
          notice_feedback: success,
          page_nums: Map.put(socket.assigns.page_nums, "notices", result.page),
          page_sizes: Map.put(socket.assigns.page_sizes, "notices", result.size)
        ]

        {:noreply, assign(socket, Keyword.merge(attrs, extra))}

      {:error, reason} ->
        message = if success, do: "#{success}，但列表刷新失败，请重试", else: "公告列表刷新失败，请重试"
        {:noreply, assign(socket, notice_feedback: Support.read_error_feedback(reason, message))}
    end
  end

  defp load_notice_page(socket, page) do
    filter = socket.assigns.notice_filter

    params = %{
      "keyword" => filter["title"] || "",
      "published" => filter["published"] || "all",
      "pageNum" => page,
      "pageSize" => get_in(socket.assigns, [:page_sizes, "notices"]) || 20
    }

    AdminReadSupport.notices_page(socket, params)
  end

  defp current_page(socket), do: get_in(socket.assigns, [:page_nums, "notices"]) || 1

  defp self_authorization(socket) do
    principal =
      (socket.assigns[:current_user] || %{})
      |> Map.put(:permissions, List.wrap(socket.assigns[:permissions]))

    %{principal: principal}
  end
end
