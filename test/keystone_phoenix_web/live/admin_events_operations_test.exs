defmodule KeystonePhoenixWeb.Live.AdminEvents.OperationsTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Live.AdminEvents.Operations

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
end
