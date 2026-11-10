defmodule KeystonePhoenixWeb.Live.LoginState do
  @moduledoc "Clears authentication and dashboard data together when a login ends."

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Job
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def reset(socket) do
    socket
    |> cancel_avatar_uploads()
    |> assign(
      username: "",
      password: "",
      login_error: nil,
      current_user: nil,
      permissions: [],
      auth_context: nil,
      panel_access: %{},
      read_only: true,
      access_token: nil,
      refresh_token: nil,
      captcha_enabled: false,
      captcha_key: nil,
      captcha_image: nil,
      active_panel: "overview",
      user_rows: [],
      dept_rows: [],
      dept_feedback: nil,
      dept_form: Support.empty_dept_form(),
      post_rows: [],
      post_feedback: nil,
      post_form: Support.empty_post_form(),
      config_rows: [],
      config_feedback: nil,
      config_form: Support.empty_config_form(),
      dict_type_rows: [],
      dict_data_rows: [],
      dict_feedback: nil,
      dict_type_form: Support.empty_dict_type_form(),
      dict_data_form: Support.empty_dict_data_form(),
      selected_dict_type: "",
      job_rows: [],
      job_feedback: nil,
      job_form: Support.empty_job_form(),
      job_targets: Job.invoke_targets(),
      job_log_rows: [],
      job_log_feedback: nil,
      page_nums: %{
        "users" => 1,
        "jobs" => 1,
        "job-logs" => 1,
        "dict-data" => 1,
        "login-logs" => 1,
        "operation-logs" => 1
      },
      page_sizes: %{
        "users" => 50,
        "jobs" => 50,
        "job-logs" => 50,
        "dict-data" => 50,
        "login-logs" => 50,
        "operation-logs" => 50
      },
      role_rows: [],
      selected_role_id: "",
      selected_role_name: "",
      allocated_role_user_rows: [],
      unallocated_role_user_rows: [],
      role_user_feedback: nil,
      role_feedback: nil,
      role_form: Support.empty_role_form(),
      menu_rows: [],
      menu_feedback: nil,
      menu_form: Support.empty_menu_form(),
      notice_rows: [],
      notice_feedback: nil,
      notice_form: Support.empty_notice_form(),
      login_log_rows: [],
      operation_log_rows: [],
      log_feedback: nil,
      user_form: Support.empty_user_form(),
      user_feedback: nil,
      profile_form: Support.empty_profile_form(),
      password_form: Support.empty_password_form(),
      profile_feedback: nil,
      monitor_server_info: %{},
      monitor_cache_info: %{},
      online_user_rows: [],
      network_status: %{},
      monitor_feedback: nil
    )
  end

  defp cancel_avatar_uploads(socket) do
    entries =
      case Map.get(socket.assigns, :uploads) do
        %{avatar: %{entries: entries}} -> entries
        _ -> []
      end

    Enum.reduce(entries, socket, fn entry, socket ->
      Phoenix.LiveView.cancel_upload(socket, :avatar, entry.ref)
    end)
  end
end
