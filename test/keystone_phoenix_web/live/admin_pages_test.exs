defmodule KeystonePhoenixWeb.AdminPagesTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.{Accounts, Operations, Organization, System}

  test "organization panels expose their LiveView events" do
    assigns = %{
      dept_rows: [],
      dept_form: %{
        "deptId" => "",
        "parentId" => "0",
        "deptName" => "",
        "orderNum" => 0,
        "status" => 1
      },
      dept_feedback: nil,
      post_rows: [],
      post_form: %{
        "postId" => "",
        "postCode" => "",
        "postName" => "",
        "postSort" => 0,
        "status" => 1
      },
      post_feedback: nil,
      role_rows: [],
      role_form: %{
        "roleId" => "",
        "roleName" => "",
        "roleKey" => "",
        "roleSort" => 0,
        "dataScope" => "ALL",
        "status" => 1
      },
      role_feedback: nil,
      menu_rows: [],
      menu_form: %{
        "menuId" => "",
        "menuName" => "",
        "parentId" => 0,
        "menuType" => 1,
        "status" => 1
      },
      menu_feedback: nil
    }

    assert render_component(
             &Organization.departments/1,
             Map.take(assigns, [:dept_rows, :dept_form, :dept_feedback])
           ) =~ "new-dept"

    assert render_component(
             &Organization.posts/1,
             Map.put(
               Map.take(assigns, [:post_rows, :post_form, :post_feedback]),
               :active_modal,
               "post"
             )
           ) =~ "save-post"

    assert render_component(
             &Organization.roles/1,
             Map.put(
               Map.take(assigns, [:role_rows, :role_form, :role_feedback]),
               :active_modal,
               "role"
             )
           ) =~ "save-role"

    role_user_assigns =
      Map.merge(assigns, %{
        role_rows: [
          %{
            "roleId" => 1,
            "roleName" => "管理员",
            "roleKey" => "admin",
            "dataScopeStr" => "全部数据",
            "userCount" => 1,
            "statusStr" => "正常",
            "roleSort" => 1,
            "status" => 1
          }
        ],
        selected_role_id: "1",
        selected_role_name: "管理员",
        allocated_role_user_rows: [],
        unallocated_role_user_rows: [%{"userId" => 2, "username" => "user", "nickname" => "普通用户"}],
        role_user_feedback: nil
      })

    assert render_component(
             &Organization.roles/1,
             Map.take(role_user_assigns, [
               :role_rows,
               :role_form,
               :role_feedback,
               :selected_role_id,
               :selected_role_name,
               :allocated_role_user_rows,
               :unallocated_role_user_rows,
               :role_user_feedback
             ])
           ) =~ "assign-role-user"

    role_html =
      render_component(
        &Organization.roles/1,
        Map.take(role_user_assigns, [
          :role_rows,
          :role_form,
          :role_feedback,
          :selected_role_id,
          :selected_role_name,
          :allocated_role_user_rows,
          :unallocated_role_user_rows,
          :role_user_feedback
        ])
      )

    assert role_html =~ ~s(phx-click="close-role-users")

    assert render_component(
             &Organization.menus/1,
             Map.put(
               Map.take(assigns, [:menu_rows, :menu_form, :menu_feedback]),
               :active_modal,
               "menu"
             )
           ) =~ "save-menu"
  end

  test "read-only organization panels hide mutation controls" do
    assigns = %{
      dept_rows: [],
      dept_form: %{"deptId" => "", "parentId" => 0, "deptName" => "", "status" => 1},
      dept_feedback: nil,
      read_only: true
    }

    html = render_component(&Organization.departments/1, assigns)
    refute html =~ "new-dept"
    refute html =~ "save-dept"
  end

  test "notice panel exposes title and publication filters" do
    html =
      render_component(&System.notices/1, %{
        notice_rows: [
          %{
            "noticeId" => "notice-1",
            "noticeTitle" => "维护公告",
            "noticeContent" => "系统维护窗口",
            "noticeType" => "announcement",
            "status" => 1,
            "published" => false,
            "remark" => "",
            "createTime" => "2026-11-15"
          }
        ],
        notice_form: %{"noticeId" => ""},
        notice_feedback: nil,
        notice_filter: %{"title" => "", "published" => "all"},
        read_only: false
      })

    assert html =~ ~s(phx-submit="filter-notices")
    assert html =~ ~s(name="noticeTitle")
    assert html =~ ~s(name="published")
    assert html =~ ~s(phx-click="reset-notice-filter")
    assert html =~ ~s(phx-click="publish-notice")
    assert html =~ "发布"

    type_filter_html =
      render_component(&System.notices/1, %{
        notice_rows: [
          %{
            "noticeId" => "notice-type-filter",
            "noticeTitle" => "维护",
            "noticeContent" => "窗口",
            "noticeType" => "announcement",
            "status" => 1,
            "published" => false,
            "remark" => "",
            "createTime" => "2026-11-15"
          }
        ],
        notice_form: %{"noticeId" => ""},
        notice_feedback: nil,
        notice_filter: %{"title" => "announcement", "published" => "all"},
        read_only: true
      })

    assert type_filter_html =~ "<strong>维护</strong>"
  end

  test "high-volume account lists render accessible pagination controls" do
    rows =
      Enum.map(1..51, fn id ->
        %{
          "userId" => id,
          "username" => "user_#{id}",
          "nickname" => "用户 #{id}",
          "status" => 1
        }
      end)

    assigns = %{
      user_rows: rows,
      user_form: %{"userId" => ""},
      user_feedback: nil,
      dept_rows: [],
      post_rows: [],
      role_rows: [],
      read_only: true,
      page_num: 1,
      page_size: 20
    }

    html = render_component(&Accounts.users/1, assigns)

    assert html =~ ~s(phx-click="paginate" phx-value-panel="users")
    assert html =~ "第 1 / 3 页，共 51 条"
    assert html =~ "user_1"
    refute html =~ "user_21"

    second_page = render_component(&Accounts.users/1, %{assigns | page_num: 2})
    assert second_page =~ "user_21"
    refute second_page =~ "user_41"

    third_page = render_component(&Accounts.users/1, %{assigns | page_num: 3})
    assert third_page =~ "user_51"
  end

  test "account, system, and operations panels render without a dashboard process" do
    account_assigns = %{
      user_rows: [],
      user_form: %{
        "userId" => "",
        "username" => "",
        "nickname" => "",
        "password" => "",
        "sex" => 2,
        "status" => 1
      },
      user_feedback: nil,
      dept_rows: [],
      post_rows: [],
      role_rows: [],
      profile_form: %{
        "nickname" => "",
        "email" => "",
        "phoneNumber" => "",
        "sex" => 2,
        "avatar" => ""
      },
      password_form: %{"oldPassword" => "", "newPassword" => ""},
      profile_feedback: nil
    }

    account_modal_assigns =
      Map.put(
        Map.take(account_assigns, [
          :user_rows,
          :user_form,
          :user_feedback,
          :dept_rows,
          :post_rows,
          :role_rows
        ]),
        :active_modal,
        "user"
      )

    assert render_component(&Accounts.users/1, account_modal_assigns) =~ "save-user"

    account_modal_html = render_component(&Accounts.users/1, account_modal_assigns)
    assert account_modal_html =~ "初始密码"
    assert account_modal_html =~ "角色"
    refute account_modal_html =~ "user-reset-password-form"

    account_html =
      render_component(
        &Accounts.users/1,
        Map.take(account_assigns, [
          :user_rows,
          :user_form,
          :user_feedback,
          :dept_rows,
          :post_rows,
          :role_rows
        ])
      )

    assert account_html =~ ~s(phx-click="refresh-users" phx-disable-with="刷新中…")
    assert account_html =~ ~s(phx-submit="filter-users")
    assert account_html =~ ~s(name="username")
    assert account_html =~ ~s(name="displayName")
    assert account_html =~ ~s(phx-click="reset-user-filter")
    refute account_html =~ ~s(class="table-scroll" role="region" tabindex="0")
    refute account_html =~ ~s(<th scope="col">用户</th>)
    refute account_html =~ "save-user"
    assert account_html =~ "没有匹配的用户"

    modal_html = render_component(&Accounts.users/1, account_modal_assigns)
    assert modal_html =~ ~s(aria-describedby="user-feedback")

    feedback_html =
      render_component(
        &Accounts.users/1,
        Map.take(%{account_assigns | user_feedback: {:error, "保存失败"}}, [
          :user_rows,
          :user_form,
          :user_feedback,
          :dept_rows,
          :post_rows,
          :role_rows
        ])
        |> Map.put(:active_modal, "user")
      )

    assert feedback_html =~ ~s(id="user-feedback")
    assert feedback_html =~ ~s(class="feedback feedback--error")
    assert feedback_html =~ ~s(role="alert")
    assert feedback_html =~ ~s(aria-live="assertive")
    assert feedback_html =~ "保存失败"

    profile_html =
      render_component(
        &Accounts.profile/1,
        Map.take(account_assigns, [:profile_form, :password_form, :profile_feedback])
      )

    assert profile_html =~ "save-profile"
    assert profile_html =~ ~s(<option value="" selected)
    assert profile_html =~ ~s(<option value="1")
    assert profile_html =~ ~s(<option value="0")
    refute profile_html =~ "profile-avatar-upload-form"

    system_assigns = %{
      config_rows: [],
      config_form: %{
        "configId" => "",
        "configName" => "",
        "configKey" => "",
        "configValue" => "",
        "configOptions" => "",
        "isAllowChange" => "true"
      },
      config_feedback: nil,
      dict_type_rows: [],
      dict_data_rows: [],
      dict_type_form: %{"dictId" => "", "dictName" => "", "dictType" => "", "status" => 1},
      dict_data_form: %{
        "dictCode" => "",
        "dictType" => "",
        "dictLabel" => "",
        "dictValue" => "",
        "dictSort" => 0,
        "isDefault" => "false",
        "status" => 1
      },
      selected_dict_type: "",
      dict_feedback: nil,
      notice_rows: [],
      notice_form: %{
        "noticeId" => "",
        "noticeTitle" => "",
        "noticeType" => "announcement",
        "noticeContent" => "",
        "status" => 1
      },
      notice_feedback: nil,
      login_log_rows: [],
      operation_log_rows: [],
      log_feedback: nil
    }

    assert render_component(
             &System.configs/1,
             Map.put(
               Map.take(system_assigns, [:config_rows, :config_form, :config_feedback]),
               :active_modal,
               "config"
             )
           ) =~ "save-config"

    config_modal_html =
      render_component(
        &System.configs/1,
        Map.put(
          Map.take(system_assigns, [:config_rows, :config_form, :config_feedback]),
          :active_modal,
          "config"
        )
      )

    assert config_modal_html =~ ~s(phx-value-modal="config" phx-disable-with="处理中…">取消</button>)

    dict_assigns =
      Map.take(system_assigns, [
        :dict_type_rows,
        :dict_data_rows,
        :dict_type_form,
        :dict_data_form,
        :selected_dict_type,
        :dict_feedback
      ])

    assert render_component(&System.dicts/1, Map.put(dict_assigns, :active_modal, "dict-data")) =~
             "save-dict-data"

    empty_dict_html =
      render_component(
        &System.dicts/1,
        dict_assigns
      )

    assert empty_dict_html =~ "选择一个字典类型"
    assert empty_dict_html =~ "选择类型后维护"

    dict_modal_html =
      render_component(
        &System.dicts/1,
        dict_assigns
        |> Map.put(:active_modal, "dict-data")
      )

    assert dict_modal_html =~ ~s(phx-value-modal="dict-data" phx-disable-with="处理中…">取消</button>)

    notice_modal_html =
      render_component(
        &System.notices/1,
        Map.put(
          Map.take(system_assigns, [:notice_rows, :notice_form, :notice_feedback]),
          :active_modal,
          "notice"
        )
      )

    assert notice_modal_html =~ "save-notice"
    assert notice_modal_html =~ ~s(phx-value-modal="notice" phx-disable-with="处理中…">取消</button>)

    assert render_component(
             &System.logs/1,
             Map.take(system_assigns, [:login_log_rows, :operation_log_rows, :log_feedback])
           ) =~ "refresh-logs"

    audit_html =
      render_component(&System.logs/1, %{
        login_log_rows: [%{"infoId" => "login-1", "username" => "admin", "status" => 1}],
        operation_log_rows: [
          %{"operationId" => "operation-1", "username" => "admin", "status" => 1}
        ],
        log_feedback: nil,
        read_only: false
      })

    refute audit_html =~ "delete-login-log"
    refute audit_html =~ "delete-operation-log"
    assert audit_html =~ "查询操作用户、动作和资源，保留只读审计记录。"
    refute audit_html =~ "保留分页、删除和只读权限控制"

    system_html =
      render_component(
        &System.configs/1,
        Map.take(system_assigns, [:config_rows, :config_form, :config_feedback])
      )

    assert system_html =~ ~s(aria-label="系统配置列表")
    assert system_html =~ ~s(<th scope="col">配置键</th>)
    assert system_html =~ "系统配置列表"
    assert system_html =~ "暂无配置数据"

    config_table_html =
      render_component(&System.configs/1, %{
        config_rows: [
          %{
            "configId" => "config-1",
            "configKey" => "site.name",
            "configValue" => "Keystone",
            "isAllowChange" => 1
          }
        ],
        config_form: %{"configId" => ""},
        config_feedback: nil,
        read_only: false
      })

    assert config_table_html =~ "delete-config"

    operations_assigns = %{
      job_rows: [
        %{
          "jobId" => 1,
          "jobCode" => "health-check",
          "jobName" => "健康检查",
          "jobGroup" => "DEFAULT",
          "invokeTarget" => "system:health",
          "cronExpression" => "* * * * * *",
          "concurrent" => 0,
          "status" => 0,
          "statusStr" => "暂停"
        }
      ],
      job_form: %{
        "jobId" => "",
        "jobName" => "",
        "jobGroup" => "DEFAULT",
        "invokeTarget" => "system:health",
        "cronExpression" => "* * * * * *",
        "status" => 1
      },
      job_targets: [
        %{"name" => "健康检查", "invokeTarget" => "system:health"}
      ],
      job_feedback: nil,
      job_log_rows: [],
      job_log_feedback: nil,
      monitor_server_info: %{},
      monitor_cache_info: %{},
      online_user_rows: [],
      network_status: %{"status" => "ONLINE", "checkedAt" => "2026-11-12T00:00:00Z"},
      monitor_feedback: nil
    }

    jobs_html =
      render_component(
        &Operations.jobs/1,
        Map.put(
          Map.take(operations_assigns, [:job_rows, :job_form, :job_targets, :job_feedback]),
          :active_modal,
          "job"
        )
      )

    assert jobs_html =~ "select-job"
    assert jobs_html =~ "toggle-all-job-selection"
    assert jobs_html =~ "delete-jobs"

    assert jobs_html =~
             ~s(phx-click="run-job" phx-value-job-id="1" phx-disable-with="执行中…" disabled)

    assert jobs_html =~ ~s(phx-value-modal="job" phx-disable-with="处理中…">取消</button>)

    filtered_jobs_html =
      render_component(
        &Operations.jobs/1,
        Map.merge(
          Map.take(operations_assigns, [:job_rows, :job_form, :job_targets, :job_feedback]),
          %{job_filter: %{"keyword" => "health-check"}, active_modal: nil}
        )
      )

    assert filtered_jobs_html =~ "健康检查"

    assert render_component(
             &Operations.job_logs/1,
             Map.take(operations_assigns, [:job_log_rows, :job_log_feedback])
           ) =~ "refresh-job-logs"

    monitor_html =
      render_component(
        &Operations.monitor/1,
        Map.take(operations_assigns, [
          :monitor_server_info,
          :monitor_cache_info,
          :online_user_rows,
          :network_status,
          :monitor_feedback
        ])
      )

    assert monitor_html =~ "refresh-monitor"
    assert monitor_html =~ "badge badge-success"
    assert monitor_html =~ "LIVE"
    assert monitor_html =~ "暂无采样数据"
    assert monitor_html =~ "系统 API 尚未返回 CPU 或内存趋势。"
    refute monitor_html =~ "CPU 使用率</text>"

    unknown_monitor_html =
      render_component(
        &Operations.monitor/1,
        Map.put(operations_assigns, :network_status, %{"status" => "DEGRADED"})
      )

    assert unknown_monitor_html =~ "badge badge-warning"
    assert unknown_monitor_html =~ "PARTIAL"
  end

  test "avatar upload errors render stable Chinese messages" do
    assert Accounts.upload_error_message(:too_large) == "文件不能超过 50 MB"
    assert Accounts.upload_error_message(:not_accepted) == "只支持 BMP、GIF、JPG、JPEG、PNG 或 WEBP 图片"
    assert Accounts.upload_error_message(:too_many_files) == "一次只能上传一个头像文件"
    assert Accounts.upload_error_message({:writer_failure, :enospc}) == "头像文件保存失败"
    assert Accounts.upload_error_message(:unexpected_error) == "头像文件无效，请重试"
  end
end
