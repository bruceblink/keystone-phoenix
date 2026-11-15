defmodule KeystonePhoenixWeb.Live.AdminEvents.OperationsTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Live.AdminEvents.Operations
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback

  test "selects and clears the current page jobs" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        job_rows: [%{"jobId" => "job-1"}, %{"jobId" => "job-2"}],
        job_filter: %{"keyword" => ""},
        page_nums: %{"jobs" => 1},
        page_sizes: %{"jobs" => 20},
        selected_job_ids: []
      }
    }

    assert {:noreply, selected} =
             Operations.handle_event(
               "toggle-all-job-selection",
               %{"selected" => "true"},
               socket
             )

    assert Enum.sort(selected.assigns.selected_job_ids) == ["job-1", "job-2"]

    assert {:noreply, cleared} =
             Operations.handle_event(
               "toggle-all-job-selection",
               %{"selected" => "false"},
               selected
             )

    assert cleared.assigns.selected_job_ids == []
  end

  test "missing task edit uses a stable resource error code" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        current_user: %{},
        permissions: ["job:update"],
        job_rows: []
      }
    }

    assert {:noreply, result} =
             Operations.handle_event("edit-job", %{"job-id" => "missing"}, socket)

    assert Feedback.code(result.assigns.job_feedback) == "resource_not_found"
    assert Feedback.message(result.assigns.job_feedback) == "找不到指定任务"
  end
end
