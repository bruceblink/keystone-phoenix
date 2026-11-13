defmodule KeystonePhoenixWeb.Plugs.OperationLog do
  @moduledoc """
  Records authenticated write requests after a controller has produced its response.

  This plug keeps the audit record on the server side and redacts credentials
  before persisting request parameters.
  """

  import Plug.Conn

  alias KeystonePhoenix.Log

  @write_methods ~w(POST PUT PATCH DELETE)
  @redacted_keys ~w(
    password
    oldpassword
    newpassword
    confirmpassword
    passwordconfirm
    accesstoken
    refreshtoken
    authorization
    captchacode
    captchacodekey
    captcha
  )
  @max_param_size 2048

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.method in @write_methods do
      register_before_send(conn, &record/1)
    else
      conn
    end
  end

  defp record(conn) do
    case conn.assigns[:current_user] do
      %{user_id: user_id, username: username} = user
      when is_binary(user_id) and is_binary(username) ->
        attrs = %{
          business_type: business_type(conn.method),
          request_method: request_method_code(conn.method),
          request_module: request_module(conn),
          called_method: called_method(conn),
          operator_ip: remote_ip(conn),
          operation_param: encode_params(conn.params),
          operation_result: response_result(conn.status),
          status: if(success_status?(conn.status), do: 1, else: 0)
        }

        _ = safe_create(attrs, user, conn)
        conn

      _ ->
        conn
    end
  end

  defp safe_create(attrs, user, conn) do
    Log.create_operation_log(attrs, user, conn.request_path, conn.method)
  rescue
    _error ->
      :ok
  end

  defp request_module(conn) do
    conn.private
    |> Map.get(:phoenix_controller)
    |> module_name()
    |> truncate(64)
  end

  defp called_method(conn) do
    action = conn.private |> Map.get(:phoenix_action, :unknown) |> to_string()
    (request_module(conn) <> "." <> action) |> truncate(128)
  end

  defp module_name(nil), do: ""

  defp module_name(module) when is_atom(module) do
    module |> inspect() |> String.trim_leading("Elixir.")
  end

  defp module_name(module), do: to_string(module)

  defp business_type("POST"), do: 1
  defp business_type("PUT"), do: 2
  defp business_type("PATCH"), do: 2
  defp business_type("DELETE"), do: 3
  defp business_type(_method), do: 0

  defp request_method_code("GET"), do: 1
  defp request_method_code("POST"), do: 2
  defp request_method_code("PUT"), do: 3
  defp request_method_code("DELETE"), do: 4
  defp request_method_code(_method), do: 0

  defp response_result(status) when is_integer(status), do: "HTTP #{status}"
  defp response_result(_status), do: ""

  defp success_status?(status) when is_integer(status), do: status in 200..399
  defp success_status?(_status), do: false

  defp remote_ip(%Plug.Conn{remote_ip: {a, b, c, d}}), do: "#{a}.#{b}.#{c}.#{d}"
  defp remote_ip(%Plug.Conn{remote_ip: remote_ip}), do: inspect(remote_ip)

  defp encode_params(params) when is_map(params) do
    params
    |> sanitize_value()
    |> Jason.encode()
    |> case do
      {:ok, encoded} -> truncate(encoded, @max_param_size)
      {:error, _reason} -> ""
    end
  end

  defp encode_params(_params), do: ""

  defp sanitize_value(%Plug.Upload{} = upload) do
    %{
      "filename" => upload.filename,
      "contentType" => upload.content_type
    }
  end

  defp sanitize_value(value) when is_map(value) do
    Enum.into(value, %{}, fn {key, value} ->
      key = to_string(key)
      {key, if(redacted_key?(key), do: "[REDACTED]", else: sanitize_value(value))}
    end)
  end

  defp sanitize_value(value) when is_list(value), do: Enum.map(value, &sanitize_value/1)
  defp sanitize_value(value) when is_binary(value), do: truncate(value, 512)

  defp sanitize_value(value) when is_number(value) or is_boolean(value) or is_nil(value),
    do: value

  defp sanitize_value(value), do: inspect(value)

  defp redacted_key?(key) do
    key
    |> String.downcase()
    |> String.replace("_", "")
    |> then(&(&1 in @redacted_keys))
  end

  defp truncate(value, length) when is_binary(value), do: String.slice(value, 0, length)
  defp truncate(value, _length), do: value
end
