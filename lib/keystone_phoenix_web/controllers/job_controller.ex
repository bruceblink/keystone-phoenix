defmodule KeystonePhoenixWeb.JobController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      list: "system:job:list",
      invoke_targets: "system:job:list",
      logs: "system:job:list",
      show: "system:job:query",
      create: "system:job:add",
      update: "system:job:edit",
      change_status: "system:job:changeStatus",
      run: "system:job:run",
      cancel: "system:job:run",
      delete: "system:job:remove"
    }

  alias KeystonePhoenix.Job
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns a paginated scheduled job list."
  def list(conn, params), do: json(conn, ApiResponse.ok(Job.list_jobs(params)))

  @doc "Returns one scheduled job."
  def show(conn, %{"job_id" => job_id}) do
    case Job.get_job(job_id) do
      {:ok, job} -> json(conn, ApiResponse.ok(Job.job_to_map(job)))
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  @doc "Returns allow-listed invocation targets."
  def invoke_targets(conn, _params), do: json(conn, ApiResponse.ok(Job.invoke_targets()))

  @doc "Returns a paginated scheduled job execution log list."
  def logs(conn, params), do: json(conn, ApiResponse.ok(Job.list_job_logs(params)))

  @doc "Creates a scheduled job."
  def create(conn, params) do
    case Job.create_job(params, conn.assigns.current_user.user_id) do
      {:ok, _job} -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Updates a scheduled job."
  def update(conn, %{"job_id" => job_id} = params) do
    case Job.update_job(job_id, params, conn.assigns.current_user.user_id) do
      {:ok, _job} -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Changes a scheduled job status."
  def change_status(conn, %{"job_id" => job_id, "status" => status}) do
    case Job.update_job_status(job_id, status, conn.assigns.current_user.user_id) do
      {:ok, _job} -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def change_status(conn, _params), do: render_error(conn, :invalid_status)

  @doc "Runs a scheduled job immediately and stores its execution log."
  def run(conn, %{"job_id" => job_id}) do
    case Job.run_job(job_id) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Cancels automatic executions currently running for a scheduled job."
  def cancel(conn, %{"job_id" => job_id}) do
    case Job.cancel_job(job_id) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, :invalid_id} -> render_error(conn, :invalid_ids)
      :not_found -> render_error(conn, :not_running)
    end
  end

  @doc "Deletes one or more scheduled jobs."
  def delete(conn, %{"jobIds" => job_ids}) do
    case Job.delete_jobs(String.split(to_string(job_ids), ",")) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def delete(conn, _params), do: render_error(conn, :invalid_ids)

  defp render_error(conn, :not_found) do
    conn |> put_status(:not_found) |> json(ApiResponse.error(10001, "找不到请求的定时任务"))
  end

  defp render_error(conn, :invalid_ids) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(10003, "任务编号无效"))
  end

  defp render_error(conn, :invalid_status) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(11206, "任务状态值无效"))
  end

  defp render_error(conn, :not_running) do
    conn |> put_status(:not_found) |> json(ApiResponse.error(11207, "没有正在运行的任务"))
  end

  defp render_error(conn, :invalid_params) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(99999, "参数无效"))
  end

  defp render_error(conn, :invoke_target_invalid) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(11201, "调用目标无效，请从候选列表选择"))
  end

  defp render_error(conn, :invoke_target_not_found) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(11202, "调用目标不存在"))
  end

  defp render_error(conn, :params_invalid) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(11205, "任务参数无效"))
  end

  defp render_error(conn, :execute_failed) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(11204, "任务执行失败"))
  end

  defp render_error(conn, :log_persist_failed) do
    conn |> put_status(:service_unavailable) |> json(ApiResponse.error(50301, "任务日志保存失败"))
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(99999, "参数校验失败", errors))
  end

  defp render_error(conn, _reason) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(99999, "任务参数无效"))
  end
end
