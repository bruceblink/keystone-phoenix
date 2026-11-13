defmodule KeystonePhoenixWeb.Live.AdminPages.Forms do
  @moduledoc """
  管理后台表单的初始值。

  每个表单使用稳定的字段结构，供登录状态和管理事件共享。
  """

  # 集中维护空表单，避免页面事件模块重复定义默认字段。
  def empty_notice_form do
    %{
      "noticeId" => "",
      "noticeTitle" => "",
      "noticeType" => 2,
      "noticeContent" => "",
      "status" => 1,
      "remark" => ""
    }
  end

  def empty_dept_form do
    %{
      "deptId" => "",
      "parentId" => "0",
      "deptName" => "",
      "orderNum" => 0,
      "leaderId" => "",
      "leaderName" => "",
      "phone" => "",
      "email" => "",
      "status" => 1
    }
  end

  def empty_post_form do
    %{
      "postId" => "",
      "postCode" => "",
      "postName" => "",
      "postSort" => 0,
      "status" => 1,
      "remark" => ""
    }
  end

  def empty_role_form do
    %{
      "roleId" => "",
      "roleName" => "",
      "roleKey" => "",
      "roleSort" => 0,
      "dataScope" => "ALL",
      "deptIdSet" => "",
      "status" => 1,
      "menuIds" => "",
      "remark" => ""
    }
  end

  def empty_menu_form do
    %{
      "menuId" => "",
      "menuName" => "",
      "menuType" => 1,
      "routerName" => "",
      "parentId" => 0,
      "path" => "",
      "isButton" => "false",
      "permission" => "",
      "metaInfo" => "{}",
      "status" => 1,
      "remark" => ""
    }
  end

  def empty_user_form do
    %{
      "userId" => "",
      "username" => "",
      "nickname" => "",
      "password" => "",
      "deptId" => "",
      "postId" => "",
      "roleId" => "",
      "email" => "",
      "phoneNumber" => "",
      "sex" => 2,
      "status" => 1,
      "remark" => ""
    }
  end

  def empty_config_form do
    %{
      "configId" => "",
      "configName" => "",
      "configKey" => "",
      "configOptions" => "",
      "configValue" => "",
      "isAllowChange" => "true",
      "remark" => ""
    }
  end

  def empty_dict_type_form do
    %{"dictId" => "", "dictName" => "", "dictType" => "", "status" => 1, "remark" => ""}
  end

  def empty_dict_data_form(dict_type \\ "") do
    %{
      "dictCode" => "",
      "dictType" => dict_type,
      "dictLabel" => "",
      "dictValue" => 0,
      "dictSort" => 0,
      "isDefault" => "false",
      "cssClass" => "",
      "listClass" => "",
      "status" => 1,
      "remark" => ""
    }
  end

  def empty_job_form do
    %{
      "jobId" => "",
      "jobName" => "",
      "jobGroup" => "DEFAULT",
      "invokeTarget" => "system:health",
      "jobParams" => "",
      "cronExpression" => "0 */5 * * * *",
      "concurrent" => 0,
      "status" => 1,
      "remark" => ""
    }
  end

  def empty_profile_form do
    %{"nickname" => "", "email" => "", "phoneNumber" => "", "sex" => 2, "avatar" => ""}
  end

  def empty_password_form do
    %{"oldPassword" => "", "newPassword" => ""}
  end
end
