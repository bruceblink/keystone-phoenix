defmodule KeystonePhoenix.Log do
  @moduledoc "Query and command boundary for login and operation logs."

  import Ecto.Query

  alias KeystonePhoenix.Log.{SysLoginInfo, SysOperationLog}
  alias KeystonePhoenix.Authz.Command
  alias KeystonePhoenix.Authz.Principal
  alias KeystonePhoenix.Pagination
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Params
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

  @doc "在检查审计资源范围后查询登录日志。"
  def list_login_logs(params, options) when is_map(params) and is_list(options) do
    with :ok <- authorize_read(options, "login-log:read") do
      {:ok, list_login_logs(params)}
    end
  end

  @doc "在检查登录日志导出权限和审计范围后查询导出页。"
  def list_login_logs_for_export(params, options) when is_map(params) and is_list(options) do
    with :ok <- authorize_read(options, "login-log:export") do
      {:ok, list_login_logs(params)}
    end
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

  @doc "在检查审计资源范围后查询操作日志。"
  def list_operation_logs(params, options) when is_map(params) and is_list(options) do
    with :ok <- authorize_read(options, "operation-log:read") do
      {:ok, list_operation_logs(params)}
    end
  end

  @doc "在检查操作日志导出权限和审计范围后查询导出页。"
  def list_operation_logs_for_export(params, options) when is_map(params) and is_list(options) do
    with :ok <- authorize_read(options, "operation-log:export") do
      {:ok, list_operation_logs(params)}
    end
  end

  def delete_login_logs(ids, options) when is_list(options) do
    with :ok <- authorize_read(options, "login-log:delete") do
      soft_delete(SysLoginInfo, :info_id, ids)
    end
  end

  def delete_login_logs(_ids, _options), do: {:error, :authorization_required}

  def delete_operation_logs(ids, options) when is_list(options) do
    with :ok <- authorize_read(options, "operation-log:delete") do
      soft_delete(SysOperationLog, :operation_id, ids)
    end
  end

  def delete_operation_logs(_ids, _options), do: {:error, :authorization_required}

  # 审计写操作统一通过资源范围授权，避免服务层直接删除日志。
  def authorize_read(options, permission),
    do: Command.authorize_resource(options, permission, :audit)

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
    metadata = Map.take(metadata, [:ip_address, :login_location, :browser, :operation_system])

    attrs =
      Map.merge(
        %{
          info_id: Identity.v7(),
          username: truncate(username, 50),
          ip_address: "",
          login_location: "",
          browser: "",
          operation_system: "",
          status: status,
          msg: truncate(message, 255),
          login_time: DateTime.utc_now(),
          deleted: false
        },
        metadata
      )

    attrs =
      Map.update!(attrs, :ip_address, &truncate(&1, 128))
      |> Map.update!(:login_location, &truncate(&1, 255))
      |> Map.update!(:browser, &truncate(&1, 50))
      |> Map.update!(:operation_system, &truncate(&1, 50))

    case Repo.insert(Ecto.Changeset.cast(%SysLoginInfo{}, attrs, Map.keys(attrs))) do
      {:ok, _log} -> :ok
      {:error, _changeset} -> :ok
    end
  rescue
    _error -> :ok
  end

  def create_operation_log(attrs, user, request_url, request_method) when is_map(attrs) do
    normalized = %{
      operation_id: Identity.v7(),
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

    normalized =
      normalized
      |> Map.update!(:request_module, &truncate(&1, 64))
      |> Map.update!(:request_url, &truncate(&1, 256))
      |> Map.update!(:called_method, &truncate(&1, 128))
      |> Map.update!(:username, &truncate(&1, 32))
      |> Map.update!(:operator_ip, &truncate(&1, 128))
      |> Map.update!(:operation_param, &truncate(&1, 2048))
      |> Map.update!(:operation_result, &truncate(&1, 2048))
      |> Map.update!(:error_stack, &truncate(&1, 2048))

    Repo.insert(Ecto.Changeset.cast(%SysOperationLog{}, normalized, Map.keys(normalized)))
  rescue
    _error -> {:error, :invalid_log}
  end

  def create_operation_log(_attrs, _user, _request_url, _request_method),
    do: {:error, :invalid_log}

  @doc "Persists a sanitized authorization decision and safe request context."
  def record_authorization_decision(principal, permission, decision, context \\ %{}) do
    subject = Principal.from_user(principal)
    outcome = authorization_outcome(decision)

    attrs = %{
      "businessType" => 0,
      "requestMethod" => 0,
      "requestModule" => "KeystonePhoenix.Authz",
      "calledMethod" => normalize_permission(permission),
      "operationParam" => Jason.encode!(authorization_audit_payload(subject, outcome, context)),
      "operationResult" => outcome,
      "status" => if(outcome == "allow", do: 1, else: 0)
    }

    user = %{user_id: canonical_uuid(subject.subject_id), username: "authz"}
    _ = create_operation_log(attrs, user, "/authz/decision", "AUTHZ")
    :ok
  rescue
    _error -> :ok
  end

  defp authorization_audit_payload(subject, outcome, context) when is_map(context) do
    %{
      "subjectId" => subject.subject_id,
      "sessionId" => context_value(context, :session_id),
      "tenantId" => context_value(context, :tenant_id) || subject.tenant_id,
      "resourceId" => sanitize_audit_value(context_value(context, :resource_id)),
      "scope" => sanitize_audit_value(context_value(context, :scope)),
      "requestId" => sanitize_audit_value(context_value(context, :request_id)),
      "outcome" => outcome,
      "reason" => outcome
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp authorization_audit_payload(subject, outcome, _context),
    do: %{"subjectId" => subject.subject_id, "outcome" => outcome, "reason" => outcome}

  defp context_value(context, key) do
    Map.get(context, key, Map.get(context, to_string(key)))
  end

  defp sanitize_audit_value(nil), do: nil
  defp sanitize_audit_value(value) when is_binary(value), do: String.slice(value, 0, 256)
  defp sanitize_audit_value(value) when is_integer(value) or is_float(value), do: value
  defp sanitize_audit_value(value) when is_atom(value), do: Atom.to_string(value)
  defp sanitize_audit_value(value), do: String.slice(inspect(value), 0, 256)

  defp canonical_uuid(value) do
    case KeystonePhoenix.Params.parse_uuid(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  def login_info_to_map(log) do
    %{
      "logId" => to_string(log.info_id),
      "infoId" => log.info_id,
      "username" => log.username,
      "ipAddress" => log.ip_address,
      "loginLocation" => log.login_location,
      "browser" => log.browser,
      "operationSystem" => log.operation_system,
      "status" => log.status,
      "statusStr" => login_status_label(log.status),
      "msg" => log.msg,
      "loginTime" => format_datetime(log.login_time)
    }
  end

  def operation_log_to_map(log) do
    %{
      "operationId" => log.operation_id,
      "businessType" => log.business_type,
      "businessTypeStr" => business_type_label(log.business_type),
      "requestMethod" => request_method_label(log.request_method),
      "requestMethodCode" => log.request_method,
      "requestModule" => log.request_module,
      "requestUrl" => log.request_url,
      "calledMethod" => log.called_method,
      "operatorType" => log.operator_type,
      "operatorTypeStr" => operator_type_label(log.operator_type),
      "userId" => log.user_id,
      "username" => log.username,
      "operatorIp" => log.operator_ip,
      "operatorLocation" => log.operator_location,
      "deptId" => log.dept_id,
      "deptName" => log.dept_name,
      "operationParam" => log.operation_param,
      "operationResult" => log.operation_result,
      "status" => log.status,
      "statusStr" => operation_status_label(log.status),
      "errorStack" => log.error_stack,
      "operationTime" => format_datetime(log.operation_time)
    }
  end

  defp paginate(query, params, count_field, mapper) do
    Pagination.page(query, params, count_field, mapper)
  end

  defp soft_delete(schema, field, ids) when is_list(ids) do
    ids = ids |> Enum.map(&parse_uuid/1) |> Enum.uniq()

    if ids == [] or Enum.any?(ids, &is_nil/1) do
      {:error, :invalid_ids}
    else
      Repo.transaction(fn ->
        {count, _} =
          Repo.update_all(
            from(log in schema, where: field(log, ^field) in ^ids and log.deleted == false),
            set: [deleted: true]
          )

        if count == length(ids) do
          :ok
        else
          Repo.rollback(:not_found)
        end
      end)
      |> case do
        {:ok, :ok} -> :ok
        {:error, reason} -> {:error, reason}
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

  defp login_status_label(1), do: "登录成功"
  defp login_status_label(2), do: "退出成功"
  defp login_status_label(3), do: "注册"
  defp login_status_label(0), do: "登录失败"
  defp login_status_label(status), do: to_string(status || "")

  defp operation_status_label(1), do: "成功"
  defp operation_status_label(0), do: "失败"
  defp operation_status_label(status), do: to_string(status || "")

  defp authorization_outcome(:ok), do: "allow"
  defp authorization_outcome({:error, reason}), do: to_string(reason)
  defp authorization_outcome(_decision), do: "unknown"

  defp normalize_permission(permission) when is_binary(permission),
    do: String.slice(String.trim(permission), 0, 128)

  defp normalize_permission(_permission), do: ""

  defp request_method_label(1), do: "GET"
  defp request_method_label(2), do: "POST"
  defp request_method_label(3), do: "PUT"
  defp request_method_label(4), do: "DELETE"
  defp request_method_label(_status), do: "UNKNOWN"

  defp business_type_label(0), do: "其他操作"
  defp business_type_label(1), do: "添加"
  defp business_type_label(2), do: "修改"
  defp business_type_label(3), do: "删除"
  defp business_type_label(4), do: "授权"
  defp business_type_label(5), do: "导出"
  defp business_type_label(6), do: "导入"
  defp business_type_label(7), do: "强退"
  defp business_type_label(type), do: to_string(type || "")

  defp operator_type_label(1), do: "其他"
  defp operator_type_label(2), do: "Web用户"
  defp operator_type_label(3), do: "手机端用户"
  defp operator_type_label(type), do: to_string(type || "")

  defp parse_uuid(value) do
    case Params.parse_uuid(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

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

  defp truncate(value, max) when is_binary(value), do: String.slice(value, 0, max)
  defp truncate(value, max), do: value |> to_string() |> String.slice(0, max)
end
