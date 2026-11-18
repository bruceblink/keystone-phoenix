defmodule KeystonePhoenixWeb.Live.AdminEvents.Config do
  @moduledoc "系统配置 LiveView 事件处理。"

  import Phoenix.Component, only: [assign: 2]
  alias KeystonePhoenix.Config
  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def handle_event("refresh-config", _params, socket) do
    if Support.panel_allowed?(socket, "configs") do
      can_refresh? = Support.permission_socket?(socket, "config:refresh")

      refresh_result =
        if can_refresh?,
          do: Config.refresh_cache(authorization: self_authorization(socket)),
          else: :ok

      case {refresh_result, load_config_page(socket, current_config_page(socket))} do
        {:ok, {:ok, page}} ->
          {:noreply,
           assign(socket,
             config_rows: page.items,
             config_total: page.total,
             config_page_num: page.page,
             config_page_size: page.size,
             config_form: Support.empty_config_form(),
             config_feedback: if(can_refresh?, do: "配置缓存已刷新", else: nil),
             active_modal: nil
           )}

        {{:error, reason}, _} ->
          {:noreply,
           assign(socket, config_feedback: Support.read_error_feedback(reason, "配置缓存刷新失败，请重试"))}

        {:ok, {:error, reason}} ->
          {:noreply,
           assign(socket, config_feedback: Support.read_error_feedback(reason, "配置列表刷新失败，请重试"))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("filter-configs", params, socket),
    do: update_config_filter(socket, String.trim(to_string(params["configKeyword"] || "")))

  def handle_event("reset-config-filter", _params, socket), do: update_config_filter(socket, "")

  def handle_event("paginate-configs", %{"page" => page}, socket) do
    case Integer.parse(to_string(page)) do
      {page, ""} when page > 0 ->
        case load_config_page(socket, page) do
          {:ok, result} ->
            {:noreply,
             assign(socket,
               config_rows: result.items,
               config_total: result.total,
               config_page_num: result.page,
               config_page_size: result.size,
               config_feedback: nil
             )}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               config_feedback: Support.read_error_feedback(reason, "配置列表读取失败，请重试")
             )}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete-config", %{"config-id" => config_id}, socket) do
    # 配置不存在时保留页面文案，并返回可检索的资源错误码。
    if Support.permission_socket?(socket, "config:update") do
      case Config.delete_config(config_id, authorization: self_authorization(socket)) do
        {:ok, _config} ->
          case load_config_page(socket, 1) do
            {:ok, page} ->
              {:noreply,
               assign(socket,
                 config_rows: page.items,
                 config_total: page.total,
                 config_page_num: page.page,
                 config_page_size: page.size,
                 config_feedback: "配置已删除",
                 active_modal: nil
               )}

            {:error, reason} ->
              {:noreply,
               assign(socket,
                 config_feedback: Support.read_error_feedback(reason, "配置已删除，但列表刷新失败，请重试"),
                 active_modal: nil
               )}
          end

        {:error, :not_found} ->
          {:noreply,
           assign(socket, config_feedback: Feedback.error(:resource_not_found, "找不到指定配置"))}

        error ->
          {:noreply, assign(socket, config_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-config", _params, socket) do
    if Support.permission_socket?(socket, "config:create") do
      {:noreply,
       assign(socket,
         config_form: Support.empty_config_form(),
         config_feedback: nil,
         active_modal: "config"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-config", %{"config-id" => config_id}, socket) do
    if Support.permission_socket?(socket, "config:update") do
      case Enum.find(socket.assigns.config_rows, &(to_string(&1["configId"]) == config_id)) do
        nil ->
          {:noreply,
           assign(socket, config_feedback: Feedback.error(:resource_not_found, "找不到指定配置"))}

        config ->
          form =
            Support.empty_config_form()
            |> Map.merge(config)
            |> Map.put("configOptions", Enum.join(config["configOptions"] || [], ","))
            |> Map.put(
              "isAllowChange",
              if(config["isAllowChange"] == 1, do: "true", else: "false")
            )

          {:noreply,
           assign(socket, config_form: form, config_feedback: nil, active_modal: "config")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-config", params, socket) do
    # 保存时按配置 ID 区分新增和编辑，避免表单打开后权限改变仍能写入。
    config_id = String.trim(params["configId"] || "")
    permission = if config_id == "", do: "config:create", else: "config:update"

    if Support.permission_socket?(socket, permission) do
      params = Support.normalize_options_param(params)

      result =
        if config_id == "",
          do: Config.create_config(params, authorization: self_authorization(socket)),
          else: Config.update_config(config_id, params, authorization: self_authorization(socket))

      case result do
        {:ok, _config} ->
          case load_config_page(socket, 1) do
            {:ok, page} ->
              {:noreply,
               assign(socket,
                 config_rows: page.items,
                 config_total: page.total,
                 config_page_num: page.page,
                 config_page_size: page.size,
                 config_form: Support.empty_config_form(),
                 active_modal: nil,
                 config_feedback: if(config_id == "", do: "配置已创建", else: "配置已更新")
               )}

            {:error, reason} ->
              {:noreply,
               assign(socket,
                 config_form: Support.empty_config_form(),
                 active_modal: nil,
                 config_feedback: Support.read_error_feedback(reason, "配置已保存，但列表刷新失败，请重试")
               )}
          end

        error ->
          {:noreply, assign(socket, config_feedback: Support.form_error(error))}
      end
    else
      {:noreply,
       assign(
         socket,
         config_feedback: Feedback.error(:permission_denied, "当前账号已失去此项配置写权限，请关闭窗口后重试")
       )}
    end
  end

  defp update_config_filter(socket, keyword) do
    if Support.panel_allowed?(socket, "configs") do
      socket = assign(socket, config_filter: %{"keyword" => keyword})

      case load_config_page(socket, 1) do
        {:ok, page} ->
          {:noreply,
           assign(socket,
             config_rows: page.items,
             config_total: page.total,
             config_page_num: page.page,
             config_page_size: page.size,
             config_feedback: nil
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             config_feedback: Support.read_error_feedback(reason, "配置列表查询失败，请重试")
           )}
      end
    else
      {:noreply, socket}
    end
  end

  defp config_filter(socket),
    do: %{"keyword" => get_in(socket.assigns, [:config_filter, "keyword"]) || ""}

  defp current_config_page(socket),
    do:
      get_in(socket.assigns, [:config_page_num]) ||
        get_in(socket.assigns, [:page_nums, "configs"]) || 1

  defp load_config_page(socket, page) do
    params =
      config_filter(socket)
      |> Map.put("pageNum", page)
      |> Map.put(
        "pageSize",
        get_in(socket.assigns, [:config_page_size]) ||
          get_in(socket.assigns, [:page_sizes, "configs"]) || 20
      )

    AdminReadSupport.config_page(socket, params)
  end

  defp self_authorization(socket) do
    principal =
      (socket.assigns[:current_user] || %{})
      |> Map.put(:permissions, List.wrap(socket.assigns[:permissions]))

    %{principal: principal}
  end
end
