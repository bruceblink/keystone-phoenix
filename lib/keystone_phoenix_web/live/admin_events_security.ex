defmodule KeystonePhoenixWeb.Live.AdminEvents.Security do
  @moduledoc "LiveView event handlers for API Key lifecycle operations."

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenixWeb.Live.AdminPages.ApiKeys
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminEvents.ApiKeyExpiryTimer
  alias KeystonePhoenixWeb.Live.AdminEvents.ApiKeyPageLoader
  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support
  alias KeystonePhoenixWeb.LoginNotifications

  def handle_event("refresh-api-keys", _params, socket) do
    if Support.panel_allowed?(socket, "api-keys") do
      {:noreply,
       load_page(
         socket,
         socket.assigns.api_key_query,
         socket.assigns.api_key_status,
         current_page(socket),
         nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-api-key", _params, socket) do
    if Support.permission_socket?(socket, "api-key:create") do
      {:noreply,
       assign(socket,
         api_key_form: ApiKeys.empty_form(),
         api_key_scope_query: "",
         api_key_feedback: nil,
         issued_api_key: nil,
         active_modal: "api-key"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-api-key", params, socket) do
    if Support.permission_socket?(socket, "api-key:create") do
      case parse_expiry(params["expiresAt"]) do
        {:ok, expires_at} ->
          scopes =
            params["scopes"]
            |> to_string()
            |> String.split(",", trim: true)
            |> Enum.map(&String.trim/1)

          result =
            if Enum.all?(scopes, &scope_allowed?(socket, &1)) do
              ApiKey.issue(
                current_user_id(socket),
                String.trim(params["name"] || ""),
                scopes,
                expires_at,
                authorization(socket)
              )
            else
              {:error, :scope_exceeds_permissions}
            end

          case result do
            {:ok, issued} ->
              socket =
                load_page(
                  socket,
                  socket.assigns.api_key_query,
                  socket.assigns.api_key_status,
                  1,
                  "API Key 已签发",
                  api_key_form: ApiKeys.empty_form(),
                  issued_api_key: issued,
                  active_modal: nil
                )

              {:noreply, LoginNotifications.refresh(socket)}

            error ->
              {:noreply, assign(socket, api_key_feedback: Support.form_error(error))}
          end

        # 日期格式错误使用专属业务码，方便用户修正输入并定位问题。
        {:error, _reason} ->
          {:noreply,
           assign(
             socket,
             api_key_feedback:
               Feedback.error(
                 :api_key_expiry_invalid,
                 "API Key 到期时间格式无效，请重新选择时间。"
               )
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("rotate-api-key", %{"id" => id}, socket) do
    if Support.permission_socket?(socket, "api-key:rotate") do
      case ApiKey.rotate(current_user_id(socket), id, authorization(socket)) do
        {:ok, issued} ->
          socket =
            load_page(
              socket,
              socket.assigns.api_key_query,
              socket.assigns.api_key_status,
              1,
              "API Key 已轮换",
              issued_api_key: issued
            )

          {:noreply, LoginNotifications.refresh(socket)}

        error ->
          {:noreply, assign(socket, api_key_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("revoke-api-key", %{"id" => id}, socket) do
    if Support.permission_socket?(socket, "api-key:revoke") do
      case ApiKey.revoke(current_user_id(socket), id, authorization(socket)) do
        :ok ->
          socket =
            load_page(
              socket,
              socket.assigns.api_key_query,
              socket.assigns.api_key_status,
              1,
              "API Key 已撤销"
            )

          {:noreply, LoginNotifications.refresh(socket)}

        error ->
          {:noreply, assign(socket, api_key_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("filter-api-keys", %{"query" => query, "status" => status}, socket) do
    {:noreply, load_page(socket, query, status, 1, nil)}
  end

  def handle_event("paginate-api-keys", %{"page" => page}, socket) do
    case Integer.parse(to_string(page)) do
      {page, ""} when page > 0 ->
        {:noreply,
         load_page(socket, socket.assigns.api_key_query, socket.assigns.api_key_status, page, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("filter-api-key-scopes", %{"scopeQuery" => query} = params, socket) do
    form =
      Map.merge(
        socket.assigns.api_key_form,
        Map.take(params, ["name", "expiresAt", "expiresAtLocal"])
      )

    {:noreply, assign(socket, api_key_scope_query: query, api_key_form: form)}
  end

  def handle_event("filter-api-key-scopes", _params, socket),
    do: {:noreply, socket}

  def handle_event("toggle-api-key-scope", %{"scope" => scope, "selected" => selected}, socket) do
    if scope_allowed?(socket, scope) do
      current = ApiKeys.scope_entries(socket.assigns[:permissions])

      selected_scopes =
        socket.assigns.api_key_form["scopes"] |> to_string() |> String.split(",", trim: true)

      scopes =
        if selected == "true",
          do: Enum.uniq([scope | selected_scopes]),
          else: List.delete(selected_scopes, scope)

      if Enum.any?(current, &(&1["permission"] == scope)) do
        {:noreply,
         assign(socket,
           api_key_form:
             Map.put(socket.assigns.api_key_form, "scopes", Enum.sort(scopes) |> Enum.join(","))
         )}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("dismiss-api-key-secret", _params, socket),
    do: {:noreply, assign(socket, issued_api_key: nil)}

  # 到期后重读有效筛选，其他筛选只更新时间以更新状态和轮换按钮。
  def handle_info({:api_key_expiry_tick, token}, socket) do
    if token == socket.assigns[:api_key_expiry_token] and
         socket.assigns.active_panel == "api-keys" do
      socket =
        assign(socket,
          api_key_expiry_timer: nil,
          api_key_expiry_token: nil,
          api_key_now: DateTime.utc_now()
        )

      if socket.assigns.api_key_status == "active" and expired_api_key_visible?(socket) do
        handle_event("refresh-api-keys", %{}, socket)
      else
        {:noreply, schedule_expiry_timer(socket)}
      end
    else
      # 已取消或替换的计时消息不能刷新当前页面。
      {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp scope_allowed?(socket, scope) do
    Enum.any?(ApiKeys.scope_entries(socket.assigns[:permissions]), &(&1["permission"] == scope))
  end

  defp current_user_id(socket),
    do: socket.assigns.current_user["userId"] || socket.assigns.current_user[:user_id]

  defp authorization(socket), do: Support.authorization_options(socket)

  defp parse_expiry(nil), do: {:ok, nil}
  defp parse_expiry(""), do: {:ok, nil}

  defp parse_expiry(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date_time, _offset} -> {:ok, date_time}
      _ -> {:error, :api_key_expiry_invalid}
    end
  end

  defp current_page(socket), do: get_in(socket.assigns, [:page_nums, "api-keys"]) || 1

  defp load_page(socket, query, status, page, success, extra \\ []) do
    reader = fn requested_page ->
      params = %{
        "keyword" => String.trim(to_string(query || "")),
        "status" => status || "all",
        "pageNum" => requested_page,
        "pageSize" => get_in(socket.assigns, [:page_sizes, "api-keys"]) || 20
      }

      AdminReadSupport.api_keys_page(socket, params)
    end

    case ApiKeyPageLoader.load(reader, page) do
      {:ok, result} ->
        socket =
          assign(
            socket,
            Keyword.merge(extra,
              api_key_query: query || "",
              api_key_status: status || "all",
              api_key_rows: result.items,
              api_key_total: result.total,
              api_key_feedback: success,
              api_key_now: DateTime.utc_now(),
              page_nums: Map.put(socket.assigns.page_nums, "api-keys", result.page),
              page_sizes: Map.put(socket.assigns.page_sizes, "api-keys", result.size)
            )
          )

        schedule_expiry_timer(socket)

      {:error, reason} ->
        feedback =
          case reason do
            # 专用代码说明分页回退期间结果再次变化，用户可刷新后重试。
            :api_key_page_changed ->
              Feedback.error(:api_key_page_changed, "列表在读取期间多次变化，请刷新后重试")

            _ ->
              Support.read_error_feedback(
                reason,
                if(success,
                  do: "#{success}，但列表刷新失败，请重试",
                  else: "API Key 列表刷新失败，请重试"
                )
              )
          end

        socket =
          assign(socket,
            api_key_feedback: feedback,
            api_key_now: DateTime.utc_now()
          )

        schedule_expiry_timer(socket)
    end
  end

  defp schedule_expiry_timer(%{assigns: %{active_panel: "api-keys"}} = socket) do
    socket = ApiKeyExpiryTimer.cancel(socket)
    now = DateTime.utc_now()

    nearest =
      Enum.reduce(socket.assigns.api_key_rows, nil, fn key, nearest ->
        if (is_nil(key.revoked_at) and key.expires_at) &&
             DateTime.compare(key.expires_at, now) == :gt do
          if is_nil(nearest) or DateTime.compare(key.expires_at, nearest) == :lt,
            do: key.expires_at,
            else: nearest
        else
          nearest
        end
      end)

    if nearest, do: ApiKeyExpiryTimer.schedule(socket, nearest), else: socket
  end

  defp schedule_expiry_timer(socket), do: ApiKeyExpiryTimer.cancel(socket)

  defp expired_api_key_visible?(socket) do
    Enum.any?(socket.assigns.api_key_rows, fn key ->
      (is_nil(key.revoked_at) and key.expires_at) &&
        DateTime.compare(key.expires_at, socket.assigns.api_key_now) != :gt
    end)
  end
end
