defmodule KeystonePhoenixWeb.JobController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      list: "job:read",
      invoke_targets: "job:read",
      logs: "job:read",
      show: "job:read",
      create: "job:create",
      update: "job:update",
      change_status: "job:update-status",
      run: "job:run",
      cancel: "job:run",
      delete: "job:delete",
      delete_single: "job:delete"
    }

  plug KeystonePhoenixWeb.Plugs.RequireResourceScope, resource: :job, defer_owner: true

  alias KeystonePhoenix.Job
  alias KeystonePhoenixWeb.ApiResponse
  alias KeystonePhoenixWeb.NativeContract

  @doc "Returns a paginated scheduled job list."
  def list(conn, params) do
    query_params = NativeContract.pagination_params(params)

    result =
      if legacy_job_query?(params) do
        Job.list_jobs(query_params, authorization: %{principal: conn.assigns.current_user})
      else
        Job.list_jobs_all(query_params, authorization: %{principal: conn.assigns.current_user})
      end

    case result do
      {:ok, page} ->
        data = if legacy_job_query?(params), do: page, else: NativeContract.jobs(page)
        json(conn, ApiResponse.ok(data))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @doc "Returns one scheduled job."
  def show(conn, %{"job_id" => job_id}) do
    case Job.get_job(job_id, authorization: %{principal: conn.assigns.current_user}) do
      {:ok, job} -> json(conn, ApiResponse.ok(native_job(job)))
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Returns allow-listed invocation targets."
  def invoke_targets(conn, _params) do
    case Job.invoke_targets(authorization: %{principal: conn.assigns.current_user}) do
      {:ok, targets} -> json(conn, ApiResponse.ok(targets))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Returns a paginated scheduled job execution log list."
  def logs(conn, params) do
    query_params = NativeContract.pagination_params(params)

    case Job.list_job_logs(query_params, authorization: %{principal: conn.assigns.current_user}) do
      {:ok, page} -> json(conn, ApiResponse.ok(NativeContract.job_logs_page(page, params)))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Creates a scheduled job."
  def create(conn, params) do
    case Job.create_job(NativeContract.job_create_params(params),
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, job} ->
        conn
        |> put_status(:created)
        |> json(ApiResponse.ok(native_job(job)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @doc "Updates a scheduled job."
  def update(conn, %{"job_id" => job_id} = params) do
    case Job.update_job(job_id, NativeContract.job_params(params),
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, job} -> json(conn, ApiResponse.ok(native_job(job)))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Changes a scheduled job status."
  def change_status(conn, %{"job_id" => job_id, "enabled" => enabled}) when is_boolean(enabled) do
    change_status(conn, %{"job_id" => job_id, "status" => if(enabled, do: 1, else: 0)})
  end

  def change_status(conn, %{"job_id" => job_id, "status" => status}) do
    case Job.update_job_status(job_id, status,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, job} -> json(conn, ApiResponse.ok(native_job(job)))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def change_status(conn, _params), do: render_error(conn, :invalid_status)

  @doc "Runs a scheduled job immediately and stores its execution log."
  def run(conn, %{"job_id" => job_id}) do
    case Job.run_job(job_id, authorization: %{principal: conn.assigns.current_user}) do
      :ok ->
        json(conn, ApiResponse.ok(%{"triggered" => true}))

      {:skipped, :already_running} ->
        json(conn, ApiResponse.ok(%{"triggered" => false}))

      {:error, :not_found} ->
        render_error(conn, :not_found)

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @doc "Cancels automatic executions currently running for a scheduled job."
  def cancel(conn, %{"job_id" => job_id}) do
    case Job.cancel_job(job_id, authorization: %{principal: conn.assigns.current_user}) do
      :ok ->
        json(conn, ApiResponse.ok())

      {:error, :invalid_id} ->
        render_error(conn, :invalid_ids)

      :not_found ->
        render_error(conn, :not_running)
    end
  end

  @doc "Deletes one or more scheduled jobs."
  def delete(conn, %{"jobIds" => job_ids}) do
    delete_jobs(conn, job_ids)
  end

  def delete(conn, _params), do: render_error(conn, :invalid_ids)

  @doc "Deletes one scheduled job."
  def delete_single(conn, %{"job_id" => job_id}) do
    case Job.delete_jobs([job_id], authorization: %{principal: conn.assigns.current_user}) do
      :ok -> json(conn, ApiResponse.ok(%{"deleted" => true}))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  defp delete_jobs(conn, job_ids) do
    ids = String.split(to_string(job_ids), ",", trim: true)

    case Job.delete_jobs(String.split(to_string(job_ids), ","),
           authorization: %{principal: conn.assigns.current_user}
         ) do
      :ok ->
        json(
          conn,
          ApiResponse.ok(%{
            "deleted" => ids |> Enum.map(&String.trim/1) |> Enum.uniq() |> length()
          })
        )

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  defp native_job(job) do
    legacy = Job.job_to_map(job)
    Map.merge(NativeContract.job(legacy), legacy)
  end

  defp legacy_job_query?(params) do
    Enum.any?(
      ["jobName", "jobGroup", "status"],
      &Map.has_key?(params, &1)
    )
  end

  defp render_error(conn, :not_found) do
    conn |> put_status(:not_found) |> json(ApiResponse.error(:validation_failed, "找不到请求的定时任务"))
  end

  defp render_error(conn, :invalid_ids) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "任务编号无效"))
  end

  defp render_error(conn, :permission_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:permission_denied, "没有操作权限"))
  end

  defp render_error(conn, :data_scope_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:data_scope_denied, "没有数据权限"))
  end

  defp render_error(conn, :invalid_status) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "任务状态值无效"))
  end

  defp render_error(conn, :not_running) do
    conn |> put_status(:not_found) |> json(ApiResponse.error(:validation_failed, "没有正在运行的任务"))
  end

  defp render_error(conn, :invalid_params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "参数无效"))
  end

  defp render_error(conn, :invoke_target_invalid) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "调用目标无效，请从候选列表选择"))
  end

  defp render_error(conn, :invoke_target_not_found) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "调用目标不存在"))
  end

  defp render_error(conn, :params_invalid) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "任务参数无效"))
  end

  defp render_error(conn, :execute_failed) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "任务执行失败"))
  end

  defp render_error(conn, :log_persist_failed) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(:authorization_unavailable, "任务日志保存失败"))
  end

  defp render_error(conn, :execution_timeout) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(:authorization_unavailable, "任务执行超时，任务已终止"))
  end

  defp render_error(conn, :resource_exhausted) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(:authorization_unavailable, "任务执行资源暂不可用"))
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "参数校验失败", errors))
  end

  defp render_error(conn, _reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "任务参数无效"))
  end
end
