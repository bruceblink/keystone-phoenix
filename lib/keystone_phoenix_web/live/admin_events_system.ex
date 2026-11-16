defmodule KeystonePhoenixWeb.Live.AdminEvents.System do
  @moduledoc "LiveView event handlers for the system domain."

  import Phoenix.Component, only: [assign: 2]
  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminEvents.Notices
  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  @notice_events ~w(refresh-notices filter-notices reset-notice-filter edit-notice new-notice cancel-notice save-notice toggle-notice-status publish-notice toggle-notice-selection toggle-all-notice-selection paginate-notices delete-notices delete-notice)

  def handle_event(event, params, socket) when event in @notice_events,
    do: Notices.handle_event(event, params, socket)

  def handle_event("refresh-dicts", _params, socket) do
    if Support.panel_allowed?(socket, "dicts") do
      case AdminReadSupport.dictionary_page(
             socket,
             socket.assigns.selected_dict_type,
             dict_page_params(socket, 1)
           ) do
        {:ok, dictionary} ->
          {:noreply,
           assign(socket,
             dict_type_rows: dictionary.types,
             dict_data_rows: dictionary.data.items,
             dict_data_total: dictionary.data.total,
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
      case AdminReadSupport.dictionary_data_page(socket, dict_type, dict_page_params(socket, 1)) do
        {:ok, page} ->
          {:noreply,
           assign(socket,
             selected_dict_type: dict_type,
             dict_data_rows: page.items,
             dict_data_total: page.total,
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

  def handle_event("paginate-dict-data", %{"page" => page}, socket) do
    case Integer.parse(to_string(page)) do
      {page, ""} when page > 0 and socket.assigns.selected_dict_type != "" ->
        case AdminReadSupport.dictionary_data_page(
               socket,
               socket.assigns.selected_dict_type,
               dict_page_params(socket, page)
             ) do
          {:ok, result} ->
            {:noreply,
             assign(socket,
               dict_data_rows: result.items,
               dict_data_total: result.total,
               page_nums: Map.put(socket.assigns.page_nums, "dict-data", result.page),
               page_sizes: Map.put(socket.assigns.page_sizes, "dict-data", result.size),
               dict_feedback: nil
             )}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               dict_feedback: Support.read_error_feedback(reason, "字典条目读取失败，请重试")
             )}
        end

      _ ->
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
          {:noreply,
           assign(socket,
             dict_feedback: Feedback.error(:resource_not_found, "找不到指定字典类型")
           )}

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
             dict_data_total: length(dictionary.data),
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
             dict_data_total: length(dictionary.data),
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
          {:noreply,
           assign(socket,
             dict_feedback: Feedback.error(:resource_not_found, "找不到指定字典数据")
           )}

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

          case AdminReadSupport.dictionary_data_page(
                 socket,
                 dict_type,
                 dict_page_params(socket, 1)
               ) do
            {:ok, page} ->
              {:noreply,
               assign(socket,
                 selected_dict_type: dict_type,
                 dict_data_rows: page.items,
                 dict_data_total: page.total,
                 page_nums: Map.put(socket.assigns.page_nums, "dict-data", 1),
                 dict_data_form: Support.empty_dict_data_form(dict_type),
                 active_modal: nil,
                 dict_feedback: if(dict_code == "", do: "字典数据已创建", else: "字典数据已更新")
               )}

            {:error, reason} ->
              {:noreply,
               assign(socket,
                 dict_feedback: Support.read_error_feedback(reason, "字典数据已保存，但列表刷新失败，请重试"),
                 active_modal: nil
               )}
          end

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
          case AdminReadSupport.dictionary_data_page(
                 socket,
                 socket.assigns.selected_dict_type,
                 dict_page_params(socket, 1)
               ) do
            {:ok, page} ->
              {:noreply,
               assign(socket,
                 dict_data_rows: page.items,
                 dict_data_total: page.total,
                 page_nums: Map.put(socket.assigns.page_nums, "dict-data", 1),
                 dict_data_form: Support.empty_dict_data_form(socket.assigns.selected_dict_type),
                 active_modal: nil,
                 dict_feedback: "字典数据已删除"
               )}

            {:error, reason} ->
              {:noreply,
               assign(socket,
                 dict_feedback: Support.read_error_feedback(reason, "字典数据已删除，但列表刷新失败，请重试"),
                 active_modal: nil
               )}
          end

        error ->
          {:noreply, assign(socket, dict_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-logs", _params, socket) do
    if Support.panel_allowed?(socket, "logs") do
      case Support.load_logs_for_socket_result(socket, current_log_filters(socket)) do
        {:ok, logs} ->
          {:noreply,
           assign(socket,
             login_log_rows: logs.login_log_rows,
             login_log_total: logs.login_log_total,
             operation_log_rows: logs.operation_log_rows,
             operation_log_total: logs.operation_log_total,
             page_nums:
               socket.assigns.page_nums
               |> Map.put("login-logs", 1)
               |> Map.put("operation-logs", 1),
             log_feedback: nil
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             log_feedback: Support.read_error_feedback(reason, "日志刷新失败，请重试")
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-login-logs", _params, socket) do
    if Support.panel_allowed?(socket, "login-logs") do
      case Support.load_logs_for_socket_result(socket, %{
             "login" => reset_log_page(Map.get(socket.assigns, :login_log_filter, %{}))
           }) do
        {:ok, logs} ->
          {:noreply,
           assign(socket,
             login_log_rows: logs.login_log_rows,
             login_log_total: logs.login_log_total,
             page_nums: Map.put(socket.assigns.page_nums, "login-logs", 1),
             log_feedback: nil
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             log_feedback: Support.read_error_feedback(reason, "登录日志刷新失败，请重试")
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-operation-logs", _params, socket) do
    if Support.panel_allowed?(socket, "operation-logs") do
      case Support.load_logs_for_socket_result(socket, %{
             "operation" => reset_log_page(Map.get(socket.assigns, :operation_log_filter, %{}))
           }) do
        {:ok, logs} ->
          {:noreply,
           assign(socket,
             operation_log_rows: logs.operation_log_rows,
             operation_log_total: logs.operation_log_total,
             page_nums: Map.put(socket.assigns.page_nums, "operation-logs", 1),
             log_feedback: nil
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             log_feedback: Support.read_error_feedback(reason, "操作审计刷新失败，请重试")
           )}
      end
    else
      {:noreply, socket}
    end
  end

  defp current_log_filters(socket) do
    %{
      "login" => reset_log_page(Map.get(socket.assigns, :login_log_filter, %{})),
      "operation" => reset_log_page(Map.get(socket.assigns, :operation_log_filter, %{}))
    }
  end

  defp reset_log_page(filter), do: Map.put(filter, "pageNum", 1)

  defp dict_page_params(socket, page) do
    %{
      "pageNum" => page,
      "pageSize" => get_in(socket.assigns, [:page_sizes, "dict-data"]) || 50
    }
  end

  defp self_authorization(socket) do
    principal =
      (socket.assigns[:current_user] || %{})
      |> Map.put(:permissions, List.wrap(socket.assigns[:permissions]))

    %{principal: principal}
  end
end
