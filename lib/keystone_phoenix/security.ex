defmodule KeystonePhoenix.Security do
  @moduledoc "安全运营指标和脱敏审计报告查询。"

  import Ecto.Query

  alias KeystonePhoenix.Authz.Command
  alias KeystonePhoenix.Auth.ApiKey.Key
  alias KeystonePhoenix.Log.{SysLoginInfo, SysOperationLog}
  alias KeystonePhoenix.Pagination
  alias KeystonePhoenix.Repo

  @default_horizon_days 30
  @max_horizon_days 90

  def metrics(options) when is_list(options) do
    with :ok <- Command.authorize_resource(options, "audit:read", :audit) do
      {:ok,
       %{
         "loginFailures" => count_login_failures(),
         "operationFailures" => count_operation_failures(),
         "windowDays" => @default_horizon_days
       }}
    end
  end

  def report(params, options) when is_map(params) and is_list(options) do
    with :ok <- Command.authorize_resource(options, "audit:read", :audit),
         {:ok, window} <- report_window(params),
         :ok <- reject_unsupported_filters(params),
         {:ok, subject_id} <- normalize_subject_id(params["subjectId"] || params[:subject_id]) do
      query =
        from(log in SysOperationLog,
          where:
            log.deleted == false and log.operation_time >= ^window.from and
              log.operation_time < ^window.to,
          order_by: [desc: log.operation_time, desc: log.operation_id]
        )

      query = filter_subject(query, subject_id)
      query = filter_actor(query, params["actor"] || params[:actor])
      page = Pagination.page(query, params, :operation_id, &operation_event/1)

      {:ok,
       %{
         "tenantScope" => "current",
         "subjectId" => subject_id,
         "from" => DateTime.to_iso8601(window.from),
         "to" => DateTime.to_iso8601(window.to),
         "apiKeys" => api_key_report(subject_id, window),
         "securityEvents" => %{
           "total" => page.total,
           "page" => page.rows,
           "pageNum" => page_number(params),
           "pageSize" => page_size(params)
         }
       }}
    end
  end

  defp count_login_failures do
    from(log in SysLoginInfo, where: log.deleted == false and log.status == 0)
    |> Repo.aggregate(:count, :info_id)
  end

  defp count_operation_failures do
    from(log in SysOperationLog, where: log.deleted == false and log.status == 0)
    |> Repo.aggregate(:count, :operation_id)
  end

  defp filter_subject(query, nil), do: query
  defp filter_subject(query, ""), do: query
  defp filter_subject(query, value), do: where(query, [log], log.user_id == ^value)

  defp filter_actor(query, nil), do: query
  defp filter_actor(query, ""), do: query
  defp filter_actor(query, value), do: where(query, [log], log.username == ^to_string(value))

  defp operation_event(log) do
    %{
      "eventId" => log.operation_id,
      "subjectId" => log.user_id,
      "actor" => log.username,
      "credentialType" => "USER_SESSION",
      "credentialId" => nil,
      "operation" => log.called_method,
      "outcome" => if(log.status == 1, do: "allow", else: "deny"),
      "reason" => log.operation_result,
      "occurredAt" => DateTime.to_iso8601(log.operation_time)
    }
  end

  defp report_window(params) do
    horizon =
      parse_positive(params["horizonDays"] || params[:horizon_days], @default_horizon_days)

    if horizon < 1 or horizon > @max_horizon_days do
      {:error, :invalid_horizon}
    else
      now = DateTime.utc_now()

      with {:ok, from_value} <- parse_instant(params["from"] || params[:from]),
           {:ok, to_value} <- parse_instant(params["to"] || params[:to]) do
        from = from_value || DateTime.add(now, -horizon * 86_400, :second)
        to = to_value || now

        if DateTime.compare(from, to) == :lt,
          do: {:ok, %{from: from, to: to, horizon_days: horizon}},
          else: {:error, :invalid_window}
      end
    end
  end

  defp reject_unsupported_filters(params) do
    if blank?(params["credentialType"] || params[:credential_type]) and
         blank?(params["credentialId"] || params[:credential_id]),
       do: :ok,
       else: {:error, :unsupported_credential_filter}
  end

  defp normalize_subject_id(nil), do: {:ok, nil}
  defp normalize_subject_id(""), do: {:ok, nil}

  defp normalize_subject_id(value) do
    case Ecto.UUID.cast(to_string(value)) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_subject_id}
    end
  end

  # API Key 生命周期统计使用持久化的撤销、轮换和到期字段，不返回凭据材料。
  defp api_key_report(subject_id, window) do
    now = DateTime.utc_now()
    horizon_days = window.horizon_days
    horizon = DateTime.add(now, horizon_days * 86_400, :second)
    subject_filter = if subject_id, do: dynamic([key], key.user_id == ^subject_id), else: true

    total = count_api_keys(subject_filter)

    active =
      count_api_keys(
        dynamic(
          [key],
          ^subject_filter and is_nil(key.revoked_at) and
            (is_nil(key.expires_at) or key.expires_at > ^now)
        )
      )

    revoked = count_api_keys(dynamic([key], ^subject_filter and not is_nil(key.revoked_at)))
    rotated = count_api_keys(dynamic([key], ^subject_filter and not is_nil(key.rotated_to)))

    expiring =
      count_api_keys(
        dynamic(
          [key],
          ^subject_filter and is_nil(key.revoked_at) and not is_nil(key.expires_at) and
            key.expires_at > ^now and key.expires_at <= ^horizon
        )
      )

    %{
      "total" => total,
      "active" => active,
      "revoked" => revoked,
      "rotated" => rotated,
      "expiring" => expiring,
      "horizonDays" => horizon_days,
      "generatedAt" => DateTime.to_iso8601(now),
      "horizonAt" => DateTime.to_iso8601(horizon),
      "windowFrom" => DateTime.to_iso8601(window.from),
      "windowTo" => DateTime.to_iso8601(window.to)
    }
  end

  defp count_api_keys(true), do: Repo.aggregate(Key, :count, :id)

  defp count_api_keys(filter) do
    from(key in Key, where: ^filter)
    |> Repo.aggregate(:count, :id)
  end

  defp parse_instant(nil), do: {:ok, nil}
  defp parse_instant(""), do: {:ok, nil}

  defp parse_instant(value) do
    case DateTime.from_iso8601(to_string(value)) do
      {:ok, instant, _offset} -> {:ok, instant}
      _ -> {:error, :invalid_time}
    end
  end

  defp parse_positive(nil, default), do: default

  defp parse_positive(value, default) do
    case Integer.parse(to_string(value)) do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end

  defp page_number(params), do: parse_positive(params["pageNum"] || params[:page_num], 1)

  defp page_size(params),
    do: min(parse_positive(params["pageSize"] || params[:page_size], 20), 100)

  defp blank?(nil), do: true
  defp blank?(value), do: String.trim(to_string(value)) == ""
end
