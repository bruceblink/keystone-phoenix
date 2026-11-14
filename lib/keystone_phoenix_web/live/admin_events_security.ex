defmodule KeystonePhoenixWeb.Live.AdminEvents.Security do
  @moduledoc "LiveView event handlers for API Key lifecycle operations."

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenixWeb.Live.AdminPages.ApiKeys
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def handle_event("refresh-api-keys", _params, socket) do
    if Support.panel_allowed?(socket, "api-keys") do
      {:noreply,
       assign(socket,
         api_key_rows: Support.load_api_keys_for_socket(socket),
         api_key_feedback: nil,
         issued_api_key: nil
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
            ApiKey.issue(
              current_user_id(socket),
              String.trim(params["name"] || ""),
              scopes,
              expires_at,
              authorization(socket)
            )

          case result do
            {:ok, issued} ->
              {:noreply,
               assign(socket,
                 api_key_rows: Support.load_api_keys_for_socket(socket),
                 api_key_form: ApiKeys.empty_form(),
                 api_key_feedback: "API Key 已签发",
                 issued_api_key: issued,
                 active_modal: nil
               )}

            error ->
              {:noreply, assign(socket, api_key_feedback: Support.form_error(error))}
          end

        {:error, _reason} ->
          {:noreply, assign(socket, api_key_feedback: Feedback.error("到期时间格式无效"))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("rotate-api-key", %{"id" => id}, socket) do
    if Support.permission_socket?(socket, "api-key:rotate") do
      case ApiKey.rotate(current_user_id(socket), id, authorization(socket)) do
        {:ok, issued} ->
          {:noreply,
           assign(socket,
             api_key_rows: Support.load_api_keys_for_socket(socket),
             api_key_feedback: "API Key 已轮换",
             issued_api_key: issued
           )}

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
          {:noreply,
           assign(socket,
             api_key_rows: Support.load_api_keys_for_socket(socket),
             api_key_feedback: "API Key 已撤销"
           )}

        error ->
          {:noreply, assign(socket, api_key_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("filter-api-keys", %{"query" => query, "status" => status}, socket) do
    {:noreply, assign(socket, api_key_query: query, api_key_status: status)}
  end

  def handle_event("dismiss-api-key-secret", _params, socket),
    do: {:noreply, assign(socket, issued_api_key: nil)}

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
end
