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
        "dataScope" => 1,
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
             Map.take(assigns, [:post_rows, :post_form, :post_feedback])
           ) =~ "save-post"

    assert render_component(
             &Organization.roles/1,
             Map.take(assigns, [:role_rows, :role_form, :role_feedback])
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

    assert render_component(
             &Organization.menus/1,
             Map.take(assigns, [:menu_rows, :menu_form, :menu_feedback])
           ) =~ "save-menu"
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

    assert render_component(
             &Accounts.users/1,
             Map.take(account_assigns, [
               :user_rows,
               :user_form,
               :user_feedback,
               :dept_rows,
               :post_rows,
               :role_rows
             ])
           ) =~ "save-user"

    assert render_component(
             &Accounts.profile/1,
             Map.take(account_assigns, [:profile_form, :password_form, :profile_feedback])
           ) =~ "save-profile"

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
        "noticeType" => 2,
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
             Map.take(system_assigns, [:config_rows, :config_form, :config_feedback])
           ) =~ "save-config"

    assert render_component(
             &System.dicts/1,
             Map.take(system_assigns, [
               :dict_type_rows,
               :dict_data_rows,
               :dict_type_form,
               :dict_data_form,
               :selected_dict_type,
               :dict_feedback
             ])
           ) =~ "save-dict-data"

    assert render_component(
             &System.notices/1,
             Map.take(system_assigns, [:notice_rows, :notice_form, :notice_feedback])
           ) =~ "save-notice"

    assert render_component(
             &System.logs/1,
             Map.take(system_assigns, [:login_log_rows, :operation_log_rows, :log_feedback])
           ) =~ "refresh-logs"

    operations_assigns = %{
      job_rows: [],
      job_form: %{
        "jobId" => "",
        "jobName" => "",
        "jobGroup" => "DEFAULT",
        "invokeTarget" => "system:health",
        "cronExpression" => "* * * * * *",
        "status" => 1
      },
      job_targets: [],
      job_feedback: nil,
      job_log_rows: [],
      job_log_feedback: nil,
      monitor_server_info: %{},
      monitor_cache_info: %{},
      online_user_rows: [],
      network_status: %{},
      monitor_feedback: nil
    }

    assert render_component(
             &Operations.jobs/1,
             Map.take(operations_assigns, [:job_rows, :job_form, :job_targets, :job_feedback])
           ) =~ "save-job"

    assert render_component(
             &Operations.job_logs/1,
             Map.take(operations_assigns, [:job_log_rows, :job_log_feedback])
           ) =~ "refresh-job-logs"

    assert render_component(
             &Operations.monitor/1,
             Map.take(operations_assigns, [
               :monitor_server_info,
               :monitor_cache_info,
               :online_user_rows,
               :network_status,
               :monitor_feedback
             ])
           ) =~ "refresh-monitor"
  end
end
