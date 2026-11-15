defmodule KeystonePhoenixWeb.AdminJobFilterTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.Operations

  test "applies job filters after submit instead of every field change" do
    html =
      render_component(&Operations.jobs/1, %{
        job_rows: [],
        job_filter: %{"keyword" => ""},
        job_feedback: nil,
        job_form: %{"jobId" => ""},
        job_targets: [],
        selected_job_ids: [],
        selected_job_id: nil,
        job_log_rows: [],
        read_only: false
      })

    assert html =~ ~s(phx-submit="filter-jobs")
    refute html =~ ~s(phx-change="filter-jobs")
  end
end
