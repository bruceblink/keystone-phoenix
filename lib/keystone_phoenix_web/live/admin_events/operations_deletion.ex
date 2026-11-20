defmodule KeystonePhoenixWeb.Live.AdminEvents.OperationsDeletion do
  @moduledoc "管理任务批量删除的确认和范围检查。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Job
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  # 只有具备删除权限且已选择任务时才打开确认框。
  def open_confirmation(socket) do
    if Support.permission_socket?(socket, "job:delete") and socket.assigns.selected_job_ids != [] do
      {:noreply, assign(socket, active_modal: "job-delete", job_feedback: nil)}
    else
      {:noreply, socket}
    end
  end

  # 只执行与页面现有选择完全相同的 ID，拒绝跳过确认框或修改提交范围。
  def delete(socket, job_ids) do
    if Support.permission_socket?(socket, "job:delete") do
      ids = String.split(job_ids, ",", trim: true)

      if socket.assigns.active_modal == "job-delete" and ids != [] and
           Enum.sort(ids) == Enum.sort(socket.assigns.selected_job_ids) do
        case Job.delete_jobs(ids, authorization(socket)) do
          :ok -> {:ok, ids}
          error -> {:error, Support.form_error(error)}
        end
      else
        {:error, Feedback.error(:validation_failed, "删除范围已变化，请重新选择任务后确认")}
      end
    else
      :ignore
    end
  end

  defp authorization(socket) do
    principal =
      (socket.assigns[:current_user] || %{})
      |> Map.put(:permissions, List.wrap(socket.assigns[:permissions]))

    [authorization: %{principal: principal, permission: "job:delete"}]
  end
end
