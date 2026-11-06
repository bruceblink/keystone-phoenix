defmodule KeystonePhoenixWeb.Live.AdminEvents.System do
  @moduledoc "LiveView event handlers for the system domain."

  import Phoenix.Component, only: [assign: 2]
  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Log
  alias KeystonePhoenix.Notice
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def handle_event("refresh-config", _params, socket) do
    if Support.admin_socket?(socket) do
      Config.refresh_cache()

      {:noreply,
       assign(socket,
         config_rows: Support.load_configs(),
         config_form: Support.empty_config_form(),
         config_feedback: "配置缓存已刷新"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-config", _params, socket) do
    if Support.admin_socket?(socket) do
      {:noreply, assign(socket, config_form: Support.empty_config_form(), config_feedback: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-config", %{"config-id" => config_id}, socket) do
    if Support.admin_socket?(socket) do
      case Enum.find(socket.assigns.config_rows, &(to_string(&1["configId"]) == config_id)) do
        nil ->
          {:noreply, assign(socket, config_feedback: "找不到指定配置")}

        config ->
          form =
            config
            |> Map.merge(Support.empty_config_form())
            |> Map.put("configOptions", Enum.join(config["configOptions"] || [], ","))
            |> Map.put(
              "isAllowChange",
              if(config["isAllowChange"] == 1, do: "true", else: "false")
            )

          {:noreply, assign(socket, config_form: form, config_feedback: nil)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-config", params, socket) do
    if Support.admin_socket?(socket) do
      config_id = String.trim(params["configId"] || "")
      params = Support.normalize_options_param(params)

      result =
        if config_id == "",
          do: Config.create_config(params),
          else: Config.update_config(config_id, params)

      case result do
        {:ok, _config} ->
          {:noreply,
           assign(socket,
             config_rows: Support.load_configs(),
             config_form: Support.empty_config_form(),
             config_feedback: if(config_id == "", do: "配置已创建", else: "配置已更新")
           )}

        error ->
          {:noreply, assign(socket, config_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-notices", _params, socket) do
    if Support.admin_socket?(socket) do
      {:noreply, assign(socket, notice_rows: Support.load_notices(), notice_feedback: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-dicts", _params, socket) do
    if Support.admin_socket?(socket) do
      dictionary = Support.load_dictionary(socket.assigns.selected_dict_type)

      {:noreply,
       assign(socket,
         dict_type_rows: dictionary.types,
         dict_data_rows: dictionary.data,
         selected_dict_type: dictionary.selected,
         dict_type_form: Support.empty_dict_type_form(),
         dict_data_form: Support.empty_dict_data_form(),
         dict_feedback: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select-dict-type", %{"dict-type" => dict_type}, socket) do
    if Support.admin_socket?(socket) do
      {:noreply,
       assign(socket,
         selected_dict_type: dict_type,
         dict_data_rows: Support.load_dict_data(dict_type),
         dict_data_form: Support.empty_dict_data_form(dict_type)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-dict-type", _params, socket) do
    if Support.admin_socket?(socket) do
      {:noreply,
       assign(socket, dict_type_form: Support.empty_dict_type_form(), dict_feedback: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-dict-type", %{"dict-id" => dict_id}, socket) do
    if Support.admin_socket?(socket) do
      case Enum.find(socket.assigns.dict_type_rows, &(to_string(&1["dictId"]) == dict_id)) do
        nil ->
          {:noreply, assign(socket, dict_feedback: "找不到指定字典类型")}

        dict_type ->
          {:noreply,
           assign(socket,
             dict_type_form: Map.merge(Support.empty_dict_type_form(), dict_type),
             dict_feedback: nil
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-dict-type", params, socket) do
    if Support.admin_socket?(socket) do
      dict_id = String.trim(params["dictId"] || "")

      result =
        if dict_id == "",
          do: Dictionary.create_dict_type(params),
          else: Dictionary.update_dict_type(dict_id, params)

      case result do
        {:ok, _dict_type} ->
          dictionary = Support.load_dictionary(socket.assigns.selected_dict_type)

          {:noreply,
           assign(socket,
             dict_type_rows: dictionary.types,
             dict_data_rows: dictionary.data,
             selected_dict_type: dictionary.selected,
             dict_type_form: Support.empty_dict_type_form(),
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
    if Support.admin_socket?(socket) do
      case Dictionary.delete_dict_type(dict_id) do
        :ok ->
          dictionary = Support.load_dictionary("")

          {:noreply,
           assign(socket,
             dict_type_rows: dictionary.types,
             dict_data_rows: dictionary.data,
             selected_dict_type: dictionary.selected,
             dict_type_form: Support.empty_dict_type_form(),
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
    if Support.admin_socket?(socket) do
      {:noreply,
       assign(socket,
         dict_data_form: Support.empty_dict_data_form(socket.assigns.selected_dict_type),
         dict_feedback: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-dict-data", %{"dict-code" => dict_code}, socket) do
    if Support.admin_socket?(socket) do
      case Enum.find(socket.assigns.dict_data_rows, &(to_string(&1["dictCode"]) == dict_code)) do
        nil ->
          {:noreply, assign(socket, dict_feedback: "找不到指定字典数据")}

        dict_data ->
          form =
            Map.merge(Support.empty_dict_data_form(), dict_data)
            |> Map.put("isDefault", if(dict_data["isDefault"], do: "true", else: "false"))

          {:noreply, assign(socket, dict_data_form: form, dict_feedback: nil)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-dict-data", params, socket) do
    if Support.admin_socket?(socket) do
      dict_code = String.trim(params["dictCode"] || "")

      result =
        if dict_code == "",
          do: Dictionary.create_dict_data(params),
          else: Dictionary.update_dict_data(dict_code, params)

      case result do
        {:ok, _dict_data} ->
          dict_type = params["dictType"] || socket.assigns.selected_dict_type

          {:noreply,
           assign(socket,
             selected_dict_type: dict_type,
             dict_data_rows: Support.load_dict_data(dict_type),
             dict_data_form: Support.empty_dict_data_form(dict_type),
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
    if Support.admin_socket?(socket) do
      case Dictionary.delete_dict_data(dict_code) do
        :ok ->
          {:noreply,
           assign(socket,
             dict_data_rows: Support.load_dict_data(socket.assigns.selected_dict_type),
             dict_data_form: Support.empty_dict_data_form(socket.assigns.selected_dict_type),
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
    if Support.admin_socket?(socket) do
      logs = Support.load_logs()

      {:noreply,
       assign(socket,
         login_log_rows: logs.login_log_rows,
         operation_log_rows: logs.operation_log_rows,
         log_feedback: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-notice", %{"notice-id" => notice_id}, socket) do
    if Support.admin_socket?(socket) do
      case Enum.find(socket.assigns.notice_rows, &(to_string(&1["noticeId"]) == notice_id)) do
        nil -> {:noreply, assign(socket, notice_feedback: "找不到指定公告")}
        notice -> {:noreply, assign(socket, notice_form: notice, notice_feedback: nil)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel-notice", _params, socket) do
    if Support.admin_socket?(socket) do
      {:noreply, assign(socket, notice_form: Support.empty_notice_form(), notice_feedback: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-notice", params, socket) do
    if Support.admin_socket?(socket) do
      notice_id = String.trim(params["noticeId"] || "")

      result =
        if notice_id == "" do
          Notice.create_notice(params, current_user_id(socket))
        else
          Notice.update_notice(notice_id, params, current_user_id(socket))
        end

      case result do
        {:ok, _notice} ->
          {:noreply,
           assign(socket,
             notice_rows: Support.load_notices(),
             notice_form: Support.empty_notice_form(),
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
    if Support.admin_socket?(socket) do
      case Notice.update_notice(notice_id, %{"status" => status}, current_user_id(socket)) do
        {:ok, _notice} ->
          {:noreply,
           assign(socket, notice_rows: Support.load_notices(), notice_feedback: "公告状态已更新")}

        {:error, :not_found} ->
          {:noreply, assign(socket, notice_feedback: "找不到指定公告")}

        {:error, changeset} ->
          {:noreply, assign(socket, notice_feedback: Support.form_error(changeset))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-notice", %{"notice-id" => notice_id}, socket) do
    if Support.admin_socket?(socket) do
      case Notice.delete_notices([notice_id]) do
        :ok ->
          {:noreply,
           assign(socket, notice_rows: Support.load_notices(), notice_feedback: "公告已删除")}

        {:error, :not_found} ->
          {:noreply, assign(socket, notice_feedback: "找不到指定公告")}

        {:error, :invalid_ids} ->
          {:noreply, assign(socket, notice_feedback: "公告编号无效")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-login-log", %{"log-id" => log_id}, socket) do
    if Support.admin_socket?(socket) do
      case Log.delete_login_logs([log_id]) do
        :ok ->
          {:noreply,
           assign(socket,
             login_log_rows: Support.load_logs().login_log_rows,
             log_feedback: "登录日志已删除"
           )}

        error ->
          {:noreply, assign(socket, log_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-operation-log", %{"log-id" => log_id}, socket) do
    if Support.admin_socket?(socket) do
      case Log.delete_operation_logs([log_id]) do
        :ok ->
          {:noreply,
           assign(socket,
             operation_log_rows: Support.load_logs().operation_log_rows,
             log_feedback: "操作日志已删除"
           )}

        error ->
          {:noreply, assign(socket, log_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  defp current_user_id(socket) do
    user = socket.assigns[:current_user] || %{}
    Map.get(user, "userId") || Map.get(user, :user_id)
  end
end
