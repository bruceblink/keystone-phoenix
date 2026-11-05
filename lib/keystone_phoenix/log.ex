defmodule KeystonePhoenix.Log do
  @moduledoc "Query and command boundary for login and operation logs."

  import Ecto.Query

  alias KeystonePhoenix.Log.{SysLoginInfo, SysOperationLog}
  alias KeystonePhoenix.Repo

  def list_login_logs(params \\ %{}) do
    query =
      from(log in SysLoginInfo,
        where: log.deleted == false,
        order_by: [desc: log.info_id]
      )

    query = filter_contains(query, :username, params["username"] || params[:username])
    query = filter_integer(query, :status, params["status"] || params[:status])
    paginate(query, params, :info_id, &login_info_to_map/1)
  end

  def list_operation_logs(params \\ %{}) do
    query =
      from(log in SysOperationLog,
        where: log.deleted == false,
        order_by: [desc: log.operation_id]
      )

    query = filter_contains(query, :username, params["username"] || params[:username])

    query =
      filter_contains(query, :request_module, params["requestModule"] || params[:request_module])

    query = filter_integer(query, :status, params["status"] || params[:status])
    paginate(query, params, :operation_id, &operation_log_to_map/1)
  end

  def delete_login_logs(ids), do: soft_delete(SysLoginInfo, :info_id, ids)
  def delete_operation_logs(ids), do: soft_delete(SysOperationLog, :operation_id, ids)

  @doc "Records a login result without persisting passwords or tokens."
  def record_login(conn, username, status, message) when is_binary(username) do
    record_login_event(username, status, message, %{
      ip_address: to_string(remote_ip(conn)),
      browser: List.first(Plug.Conn.get_req_header(conn, "user-agent")) || ""
    })
  end

  def record_login(_conn, _username, _status, _message), do: :ok

  @doc "Records a login result from a non-HTTP entry point such as LiveView."
  def record_login_event(username, status, message, metadata \\ %{})

  def record_login_event(username, status, message, metadata) when is_binary(username) do
    attrs =
      Map.merge(
        %{
          username: username,
          ip_address: "",
          login_location: "",
          browser: "",
          operation_system: "",
          status: status,
          msg: message,
          login_time: DateTime.utc_now(),
          deleted: false
        },
        metadata
      )

    case Repo.insert(Ecto.Changeset.cast(%SysLoginInfo{}, attrs, Map.keys(attrs))) do
      {:ok, _log} -> :ok
      {:error, _changeset} -> :ok
    end
  end

  def create_operation_log(attrs, user, request_url, request_method) when is_map(attrs) do
    normalized = %{
      business_type: attrs["businessType"] || attrs[:business_type] || 0,
      request_method:
        attrs["requestMethod"] || attrs[:request_method] || request_method_code(request_method),
      request_module: attrs["requestModule"] || attrs[:request_module] || "",
      request_url: request_url,
      called_method: attrs["calledMethod"] || attrs[:called_method] || "",
      operator_type: 1,
      user_id: user.user_id,
      username: user.username,
      operator_ip: attrs["operatorIp"] || attrs[:operator_ip] || "",
      operation_param: attrs["operationParam"] || attrs[:operation_param] || "",
      operation_result: attrs["operationResult"] || attrs[:operation_result] || "",
      status: attrs["status"] || attrs[:status] || 1,
      error_stack: attrs["errorStack"] || attrs[:error_stack] || "",
      operation_time: DateTime.utc_now(),
      deleted: false
    }

    Repo.insert(Ecto.Changeset.cast(%SysOperationLog{}, normalized, Map.keys(normalized)))
  end

  def create_operation_log(_attrs, _user, _request_url, _request_method),
    do: {:error, :invalid_log}

  def login_info_to_map(log) do
    %{
      "infoId" => log.info_id,
      "username" => log.username,
      "ipAddress" => log.ip_address,
      "loginLocation" => log.login_location,
      "browser" => log.browser,
      "operationSystem" => log.operation_system,
      "status" => log.status,
      "msg" => log.msg,
      "loginTime" => format_datetime(log.login_time)
    }
  end

  def operation_log_to_map(log) do
    %{
      "operationId" => log.operation_id,
      "businessType" => log.business_type,
      "requestMethod" => log.request_method,
      "requestModule" => log.request_module,
      "requestUrl" => log.request_url,
      "calledMethod" => log.called_method,
      "operatorType" => log.operator_type,
      "userId" => log.user_id,
      "username" => log.username,
      "operatorIp" => log.operator_ip,
      "operationParam" => log.operation_param,
      "operationResult" => log.operation_result,
      "status" => log.status,
      "errorStack" => log.error_stack,
      "operationTime" => format_datetime(log.operation_time)
    }
  end

  defp paginate(query, params, count_field, mapper) do
    page = positive_integer(params["pageNum"] || params[:page_num], 1)
    page_size = min(positive_integer(params["pageSize"] || params[:page_size], 10), 500)
    total = Repo.aggregate(query, :count, count_field)
    rows = query |> limit(^page_size) |> offset(^((page - 1) * page_size)) |> Repo.all()
    %{total: total, rows: Enum.map(rows, mapper)}
  end

  defp soft_delete(schema, field, ids) when is_list(ids) do
    ids = ids |> Enum.map(&parse_positive_integer/1) |> Enum.uniq()

    if ids == [] or Enum.any?(ids, &is_nil/1) do
      {:error, :invalid_ids}
    else
      case Repo.update_all(
             from(log in schema, where: field(log, ^field) in ^ids and log.deleted == false),
             set: [deleted: true]
           ) do
        {count, _} when count == length(ids) -> :ok
        _ -> {:error, :not_found}
      end
    end
  end

  defp soft_delete(_schema, _field, _ids), do: {:error, :invalid_ids}

  defp filter_contains(query, _field, nil), do: query
  defp filter_contains(query, _field, ""), do: query

  defp filter_contains(query, field, value) do
    pattern = "%" <> String.trim(to_string(value)) <> "%"
    where(query, [log], ilike(field(log, ^field), ^pattern))
  end

  defp filter_integer(query, _field, nil), do: query
  defp filter_integer(query, _field, ""), do: query

  defp filter_integer(query, field, value) do
    case Integer.parse(to_string(value)) do
      {number, ""} -> where(query, [log], field(log, ^field) == ^number)
      _ -> query
    end
  end

  defp positive_integer(nil, default), do: default

  defp positive_integer(value, default) do
    case Integer.parse(to_string(value)) do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} when number > 0 -> number
      _ -> nil
    end
  end

  defp parse_positive_integer(_value), do: nil

  defp request_method_code(method) when method in ["GET", "POST", "PUT", "DELETE"],
    do: %{"GET" => 1, "POST" => 2, "PUT" => 3, "DELETE" => 4}[method]

  defp request_method_code(_method), do: 0

  defp remote_ip(%Plug.Conn{remote_ip: {a, b, c, d}}), do: "#{a}.#{b}.#{c}.#{d}"
  defp remote_ip(%Plug.Conn{remote_ip: remote_ip}), do: inspect(remote_ip)

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
