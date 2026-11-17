defmodule KeystonePhoenixWeb.Live.AdminEvents.Security do
  @moduledoc "LiveView event handlers for API Key lifecycle operations."

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenixWeb.Live.AdminPages.ApiKeys
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
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

        # 日期解析失败属于输入校验错误，反馈使用稳定错误码。
        {:error, _reason} ->
          {:noreply,
           assign(
             socket,
             api_key_feedback: Feedback.error(:validation_failed, "到期时间格式无效")
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
      Map.merge(socket.assigns.api_key_form, Map.take(params, ["name", "expiresAt"]))

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
      _ -> {:error, :invalid_expiry}
    end
  end

  defp current_page(socket), do: get_in(socket.assigns, [:page_nums, "api-keys"]) || 1

  defp load_page(socket, query, status, page, success, extra \\ []) do
    params = %{
      "keyword" => String.trim(to_string(query || "")),
      "status" => status || "all",
      "pageNum" => page,
      "pageSize" => get_in(socket.assigns, [:page_sizes, "api-keys"]) || 20
    }

    socket =
      assign(socket,
        api_key_query: query || "",
        api_key_status: status || "all",
        page_nums: Map.put(socket.assigns.page_nums, "api-keys", page)
      )

    case AdminReadSupport.api_keys_page(socket, params) do
      {:ok, result} ->
        assign(
          socket,
          Keyword.merge(extra,
            api_key_rows: result.items,
            api_key_total: result.total,
            api_key_feedback: success,
            page_nums: Map.put(socket.assigns.page_nums, "api-keys", result.page),
            page_sizes: Map.put(socket.assigns.page_sizes, "api-keys", result.size)
          )
        )

      {:error, reason} ->
        assign(socket,
          api_key_feedback:
            Support.read_error_feedback(
              reason,
              if(success, do: "#{success}，但列表刷新失败，请重试", else: "API Key 列表刷新失败，请重试")
            )
        )
    end
  end
end
