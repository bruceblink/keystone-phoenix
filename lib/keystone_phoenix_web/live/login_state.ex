defmodule KeystonePhoenixWeb.Live.LoginState do
  @moduledoc "Clears authentication and dashboard data together when a login ends."

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Job
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def reset(socket) do
    socket
    |> cancel_avatar_uploads()
    |> cancel_notification_load()
    |> assign(
      username: "operator",
      password: "keystone",
      login_error: nil,
      login_notice: nil,
      initial_password_required: false,
      initial_password_error: nil,
      login_confirm_open: false,
      pending_login: nil,
      pending_mfa_login: false,
      mfa_challenge: nil,
      mfa_username: "",
      mfa_force_login: false,
      mfa_code: "",
      mfa_error: nil,
      mfa_step_up_required: false,
      mfa_step_up_challenge: nil,
      mfa_step_up_code: "",
      mfa_step_up_error: nil,
      mfa_step_up_notice: nil,
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
      active_panel: "monitor",
      current_uri: "/",
      sidebar_open: false,
      notifications_open: false,
      notifications_loading: false,
      notifications_error: nil,
      notification_read_error: nil,
      notification_read_error_action: nil,
      notification_read_error_label: nil,
      notifications_user_id: nil,
      notifications_async_name: nil,
      notifications_unread_count: 0,
      notifications_page: 1,
      notifications_has_more: false,
      selected_notification_id: nil,
      in_app_notifications: [],
      active_modal: nil,
      user_rows: [],
      user_total: 0,
      users_server_paged: false,
      selected_user_ids: [],
      user_import_result: nil,
      user_query: "",
      user_display_name_query: "",
      dept_rows: [],
      dept_feedback: nil,
      dept_form: Support.empty_dept_form(),
      dept_filter: %{"keyword" => "", "status" => "all"},
      post_rows: [],
      post_total: 0,
      post_feedback: nil,
      post_form: Support.empty_post_form(),
      post_filter: %{"keyword" => "", "status" => "all"},
      config_rows: [],
      config_total: 0,
      config_feedback: nil,
      config_form: Support.empty_config_form(),
      config_filter: %{"keyword" => ""},
      dict_type_rows: [],
      dict_data_rows: [],
      dict_data_total: 0,
      dict_feedback: nil,
      dict_type_form: Support.empty_dict_type_form(),
      dict_data_form: Support.empty_dict_data_form(),
      dict_data_filter: %{"keyword" => ""},
      selected_dict_type: "",
      job_rows: [],
      job_total: 0,
      selected_job_ids: [],
      selected_job_id: nil,
      selected_job: nil,
      job_filter: %{"keyword" => ""},
      job_feedback: nil,
      job_form: Support.empty_job_form(),
      job_targets: Job.invoke_targets(),
      job_log_rows: [],
      job_log_total: 0,
      job_log_feedback: nil,
      job_log_loaded_page: nil,
      page_nums: %{
        "users" => 1,
        "posts" => 1,
        "jobs" => 1,
        "roles" => 1,
        "configs" => 1,
        "notices" => 1,
        "api-keys" => 1,
        "job-logs" => 1,
        "dict-data" => 1,
        "login-logs" => 1,
        "operation-logs" => 1,
        "online-users" => 1,
        "role-users-allocated" => 1,
        "role-users-unallocated" => 1
      },
      page_sizes: %{
        "users" => 20,
        "posts" => 20,
        "jobs" => 20,
        "roles" => 20,
        "configs" => 20,
        "notices" => 20,
        "api-keys" => 20,
        "job-logs" => 20,
        "dict-data" => 50,
        "login-logs" => 20,
        "operation-logs" => 20,
        "online-users" => 50,
        "role-users-allocated" => 50,
        "role-users-unallocated" => 50
      },
      role_rows: [],
      role_directory_feedback: nil,
      role_page_rows: [],
      role_total: 0,
      selected_role_ids: [],
      selected_role_id: "",
      selected_role_name: "",
      role_filter: %{"keyword" => "", "status" => "all"},
      allocated_role_user_rows: [],
      unallocated_role_user_rows: [],
      role_user_feedback: nil,
      role_feedback: nil,
      role_form: Support.empty_role_form(),
      role_permission_query: "",
      menu_rows: [],
      menu_feedback: nil,
      menu_form: Support.empty_menu_form(),
      menu_filter: "",
      menu_role_codes: [],
      api_key_rows: [],
      api_key_total: 0,
      api_key_feedback: nil,
      api_key_form: %{"name" => "", "scopes" => "", "expiresAt" => ""},
      api_key_query: "",
      api_key_status: "all",
      api_key_scope_query: "",
      issued_api_key: nil,
      notice_rows: [],
      notice_total: 0,
      notice_retry_page: nil,
      selected_notice_ids: [],
      notice_feedback: nil,
      notice_filter: %{"title" => "", "published" => "all"},
      notice_form: Support.empty_notice_form(),
      login_log_rows: [],
      login_log_total: 0,
      operation_log_rows: [],
      operation_log_total: 0,
      login_log_filter: %{"username" => "", "status" => ""},
      operation_log_filter: %{"actor" => "", "action" => "", "resource" => ""},
      dict_type_filter: %{"keyword" => ""},
      log_feedback: nil,
      user_form: Support.empty_user_form(),
      user_feedback: nil,
      profile_form: Support.empty_profile_form(),
      profile_baseline_form: nil,
      profile_dirty: false,
      password_form: Support.empty_password_form(),
      profile_loaded: false,
      profile_feedback: nil,
      monitor_server_info: %{},
      monitor_cache_info: %{},
      online_user_rows: [],
      online_user_total: 0,
      network_status: %{},
      monitor_help_open: false,
      security_access: false,
      security_metrics: %{},
      security_api_keys: %{},
      security_event_rows: [],
      security_event_total: 0,
      monitor_loaded: false,
      monitor_feedback: nil,
      monitor_loading: false,
      monitor_initial_error: nil
    )
  end

  defp cancel_avatar_uploads(socket) do
    cancel_uploads(socket, :avatar)
    |> cancel_uploads(:user_import)
  end

  # 登录结束时取消待处理的收件箱读取，避免旧账号通知进入新会话。
  defp cancel_notification_load(socket) do
    case socket.assigns[:notifications_async_name] do
      nil -> socket
      async_name -> Phoenix.LiveView.cancel_async(socket, async_name)
    end
  end

  # 注销时取消尚未消费的上传，避免文件继续占用 LiveView 临时目录。
  defp cancel_uploads(socket, name) do
    entries =
      case Map.get(socket.assigns, :uploads) do
        uploads when is_map(uploads) ->
          case Map.get(uploads, name) do
            %{entries: entries} -> entries
            _ -> []
          end

        _ ->
          []
      end

    Enum.reduce(entries, socket, fn entry, socket ->
      Phoenix.LiveView.cancel_upload(socket, name, entry.ref)
    end)
  end
end
