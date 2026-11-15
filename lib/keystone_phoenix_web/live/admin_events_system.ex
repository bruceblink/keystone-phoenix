defmodule KeystonePhoenixWeb.Live.AdminEvents.System do
  @moduledoc "LiveView event handlers for the system domain."

  import Phoenix.Component, only: [assign: 2]
  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Notice
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminPages.System, as: NoticePage
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def handle_event("refresh-notices", _params, socket) do
    if Support.panel_allowed?(socket, "notices") do
      case Support.load_notices_for_socket_result(socket) do
        {:ok, rows} ->
          {:noreply,
           assign(socket,
             notice_rows: rows,
             selected_notice_ids: [],
             notice_feedback: nil,
             active_modal: nil
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             notice_feedback: Support.read_error_feedback(reason, "公告列表刷新失败，请重试")
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("filter-notices", params, socket) do
    if Support.panel_allowed?(socket, "notices") do
      {:noreply,
       assign(socket,
         selected_notice_ids: [],
         notice_filter: %{
           "title" => String.trim(params["noticeTitle"] || ""),
           "published" => params["published"] || "all"
         }
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reset-notice-filter", _params, socket) do
    if Support.panel_allowed?(socket, "notices") do
      {:noreply,
       assign(socket,
         selected_notice_ids: [],
         notice_filter: %{"title" => "", "published" => "all"}
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-dicts", _params, socket) do
    if Support.panel_allowed?(socket, "dicts") do
      case Support.load_dictionary_for_socket_result(socket, socket.assigns.selected_dict_type) do
        {:ok, dictionary} ->
          {:noreply,
           assign(socket,
             dict_type_rows: dictionary.types,
             dict_data_rows: dictionary.data,
             page_nums: Map.put(socket.assigns.page_nums, "dict-data", 1),
             selected_dict_type: dictionary.selected,
             dict_type_form: Support.empty_dict_type_form(),
             dict_data_form: Support.empty_dict_data_form(),
             dict_feedback: nil,
             active_modal: nil
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             dict_feedback: Support.read_error_feedback(reason, "字典数据刷新失败，请重试")
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("select-dict-type", %{"dict-type" => dict_type}, socket) do
    if Support.panel_allowed?(socket, "dicts") and
         Support.dict_type_allowed?(socket, dict_type) do
      case Support.load_dict_data_for_socket_result(socket, dict_type) do
        {:ok, rows} ->
          {:noreply,
           assign(socket,
             selected_dict_type: dict_type,
             dict_data_rows: rows,
             dict_data_form: Support.empty_dict_data_form(dict_type),
             page_nums: Map.put(socket.assigns.page_nums, "dict-data", 1),
             dict_feedback: nil,
             active_modal: nil
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             dict_feedback: Support.read_error_feedback(reason, "字典条目读取失败，请重试")
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-dict-type", _params, socket) do
    if Support.permission_socket?(socket, "dictionary:create") do
      {:noreply,
       assign(socket,
         dict_type_form: Support.empty_dict_type_form(),
         dict_feedback: nil,
         active_modal: "dict-type"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-dict-type", %{"dict-id" => dict_id}, socket) do
    if Support.permission_socket?(socket, "dictionary:update") do
      case Enum.find(socket.assigns.dict_type_rows, &(to_string(&1["dictId"]) == dict_id)) do
        nil ->
          {:noreply, assign(socket, dict_feedback: Feedback.error("找不到指定字典类型"))}

        dict_type ->
          {:noreply,
           assign(socket,
             dict_type_form: Map.merge(Support.empty_dict_type_form(), dict_type),
             dict_feedback: nil,
             active_modal: "dict-type"
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-dict-type", params, socket) do
    if Support.permission_socket?(socket, "dictionary:create") or
         Support.permission_socket?(socket, "dictionary:update") do
      dict_id = String.trim(params["dictId"] || "")

      result =
        if dict_id == "",
          do: Dictionary.create_dict_type(params, authorization: self_authorization(socket)),
          else:
            Dictionary.update_dict_type(dict_id, params,
              authorization: self_authorization(socket)
            )

      case result do
        {:ok, _dict_type} ->
          dictionary =
            Support.load_dictionary_for_socket(socket, socket.assigns.selected_dict_type)

          {:noreply,
           assign(socket,
             dict_type_rows: dictionary.types,
             dict_data_rows: dictionary.data,
             selected_dict_type: dictionary.selected,
             dict_type_form: Support.empty_dict_type_form(),
             active_modal: nil,
             dict_feedback: if(dict_id == "", do: "字典类型已创建", else: "字典类型已更新")
           )}

        error ->
          {:noreply, assign(socket, dict_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-dict-type", %{"dict-id" => dict_id}, socket) do
    if Support.permission_socket?(socket, "dictionary:delete") do
      case Dictionary.delete_dict_type(dict_id, authorization: self_authorization(socket)) do
        :ok ->
          dictionary = Support.load_dictionary_for_socket(socket, "")

          {:noreply,
           assign(socket,
             dict_type_rows: dictionary.types,
             dict_data_rows: dictionary.data,
             selected_dict_type: dictionary.selected,
             dict_type_form: Support.empty_dict_type_form(),
             active_modal: nil,
             dict_feedback: "字典类型已删除"
           )}

        error ->
          {:noreply, assign(socket, dict_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-dict-data", _params, socket) do
    if Support.permission_socket?(socket, "dictionary:create") do
      {:noreply,
       assign(socket,
         dict_data_form: Support.empty_dict_data_form(socket.assigns.selected_dict_type),
         dict_feedback: nil,
         active_modal: "dict-data"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-dict-data", %{"dict-code" => dict_code}, socket) do
    if Support.permission_socket?(socket, "dictionary:update") do
      case Enum.find(socket.assigns.dict_data_rows, &(to_string(&1["dictCode"]) == dict_code)) do
        nil ->
          {:noreply, assign(socket, dict_feedback: Feedback.error("找不到指定字典数据"))}

        dict_data ->
          form =
            Map.merge(Support.empty_dict_data_form(), dict_data)
            |> Map.put("isDefault", if(dict_data["isDefault"] == 1, do: "true", else: "false"))

          {:noreply,
           assign(socket, dict_data_form: form, dict_feedback: nil, active_modal: "dict-data")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-dict-data", params, socket) do
    if Support.permission_socket?(socket, "dictionary:create") or
         Support.permission_socket?(socket, "dictionary:update") do
      dict_code = String.trim(params["dictCode"] || "")

      result =
        if dict_code == "",
          do: Dictionary.create_dict_data(params, authorization: self_authorization(socket)),
          else:
            Dictionary.update_dict_data(dict_code, params,
              authorization: self_authorization(socket)
            )

      case result do
        {:ok, _dict_data} ->
          dict_type = params["dictType"] || socket.assigns.selected_dict_type

          {:noreply,
           assign(socket,
             selected_dict_type: dict_type,
             dict_data_rows:
               Support.load_dict_data(dict_type, Support.authorization_options(socket)),
             dict_data_form: Support.empty_dict_data_form(dict_type),
             active_modal: nil,
             dict_feedback: if(dict_code == "", do: "字典数据已创建", else: "字典数据已更新")
           )}

        error ->
          {:noreply, assign(socket, dict_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-dict-data", %{"dict-code" => dict_code}, socket) do
    if Support.permission_socket?(socket, "dictionary:delete") do
      case Dictionary.delete_dict_data(dict_code, authorization: self_authorization(socket)) do
        :ok ->
          {:noreply,
           assign(socket,
             dict_data_rows:
               Support.load_dict_data(
                 socket.assigns.selected_dict_type,
                 Support.authorization_options(socket)
               ),
             dict_data_form: Support.empty_dict_data_form(socket.assigns.selected_dict_type),
             active_modal: nil,
             dict_feedback: "字典数据已删除"
           )}

        error ->
          {:noreply, assign(socket, dict_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-logs", _params, socket) do
    if Support.panel_allowed?(socket, "logs") do
      logs = Support.load_logs_for_socket(socket)

      {:noreply,
       assign(socket,
         login_log_rows: logs.login_log_rows,
         operation_log_rows: logs.operation_log_rows,
         page_nums:
           socket.assigns.page_nums
           |> Map.put("login-logs", 1)
           |> Map.put("operation-logs", 1),
         log_feedback: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-login-logs", _params, socket) do
    if Support.panel_allowed?(socket, "login-logs") do
      {:noreply,
       assign(socket,
         login_log_rows: Support.load_logs_for_socket(socket).login_log_rows,
         page_nums: Map.put(socket.assigns.page_nums, "login-logs", 1),
         log_feedback: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-operation-logs", _params, socket) do
    if Support.panel_allowed?(socket, "operation-logs") do
      {:noreply,
       assign(socket,
         operation_log_rows: Support.load_logs_for_socket(socket).operation_log_rows,
         page_nums: Map.put(socket.assigns.page_nums, "operation-logs", 1),
         log_feedback: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-notice", %{"notice-id" => notice_id}, socket) do
    if Support.permission_socket?(socket, "notice:update") do
      case Enum.find(socket.assigns.notice_rows, &(to_string(&1["noticeId"]) == notice_id)) do
        nil ->
          {:noreply, assign(socket, notice_feedback: Feedback.error("找不到指定公告"))}

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
        if notice_id == "" do
          Notice.create_notice(params, authorization: self_authorization(socket))
        else
          Notice.update_notice(notice_id, params, authorization: self_authorization(socket))
        end

      case result do
        {:ok, _notice} ->
          {:noreply,
           assign(socket,
             notice_rows: Support.load_notices_for_socket(socket),
             selected_notice_ids: [],
             notice_form: Support.empty_notice_form(),
             active_modal: nil,
             notice_feedback: if(notice_id == "", do: "公告已创建", else: "公告已更新")
           )}

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
          {:noreply,
           assign(socket,
             notice_rows: Support.load_notices_for_socket(socket),
             selected_notice_ids: [],
             notice_feedback: "公告状态已更新"
           )}

        {:error, :not_found} ->
          {:noreply, assign(socket, notice_feedback: Feedback.error("找不到指定公告"))}

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
      case Notice.publish_notice(
             notice_id,
             published == "true",
             authorization: self_authorization(socket)
           ) do
        {:ok, _notice} ->
          message = if published == "true", do: "公告已发布", else: "公告已取消发布"

          {:noreply,
           assign(socket,
             notice_rows: Support.load_notices_for_socket(socket),
             selected_notice_ids: [],
             notice_feedback: message
           )}

        {:error, :not_found} ->
          {:noreply, assign(socket, notice_feedback: Feedback.error("找不到指定公告"))}

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
    selected_ids = Map.get(socket.assigns, :selected_notice_ids, [])

    selected_ids =
      if selected == "true",
        do: Enum.uniq([notice_id | selected_ids]),
        else: List.delete(selected_ids, notice_id)

    {:noreply, assign(socket, selected_notice_ids: selected_ids)}
  end

  def handle_event("toggle-all-notice-selection", %{"selected" => selected}, socket) do
    rows =
      NoticePage.filtered_notice_rows(socket.assigns.notice_rows, socket.assigns.notice_filter)

    page_ids = Enum.map(rows, &to_string(&1["noticeId"]))
    selected_ids = Map.get(socket.assigns, :selected_notice_ids, [])

    selected_ids =
      if selected == "true",
        do: Enum.uniq(selected_ids ++ page_ids),
        else: selected_ids -- page_ids

    {:noreply, assign(socket, selected_notice_ids: selected_ids)}
  end

  def handle_event("delete-notices", %{"notice-ids" => ids}, socket) do
    if Support.permission_socket?(socket, "notice:delete") do
      notice_ids = String.split(ids || "", ",", trim: true)

      case Notice.delete_notices(notice_ids, authorization: self_authorization(socket)) do
        :ok ->
          {:noreply,
           assign(socket,
             notice_rows: Support.load_notices_for_socket(socket),
             selected_notice_ids: [],
             notice_feedback: "公告已删除",
             active_modal: nil
           )}

        {:error, :not_found} ->
          {:noreply, assign(socket, notice_feedback: Feedback.error("找不到指定公告"))}

        {:error, :invalid_ids} ->
          {:noreply, assign(socket, notice_feedback: Feedback.error("公告编号无效"))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-notice", %{"notice-id" => notice_id}, socket) do
    handle_event("delete-notices", %{"notice-ids" => notice_id}, socket)
  end

  defp self_authorization(socket) do
    principal =
      (socket.assigns[:current_user] || %{})
      |> Map.put(:permissions, List.wrap(socket.assigns[:permissions]))

    %{principal: principal}
  end
end
