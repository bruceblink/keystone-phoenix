defmodule KeystonePhoenix.SystemManagementSchemaTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Dictionary.DictData
  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Notice.SysNotice
  alias KeystonePhoenix.Log.{SysLoginInfo, SysOperationLog}
  alias KeystonePhoenix.Post.SysPost
  alias KeystonePhoenix.Role.SysRole

  test "department changeset validates the enabled status" do
    changeset = SysDept.changeset(%SysDept{}, %{dept_name: "研发", status: 2})
    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :status)
  end

  test "post changeset requires a stable code and name" do
    changeset = SysPost.changeset(%SysPost{}, %{post_sort: 1, status: 1})
    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :post_code)
    assert Keyword.has_key?(changeset.errors, :post_name)
  end

  test "role changeset rejects unsupported data scopes" do
    changeset =
      SysRole.changeset(%SysRole{}, %{
        role_name: "普通角色",
        role_key: "common",
        role_sort: 1,
        data_scope: 9,
        status: 1
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :data_scope)
  end

  test "menu changeset validates menu type and status" do
    changeset =
      SysMenu.changeset(%SysMenu{}, %{
        menu_name: "用户管理",
        menu_type: 9,
        parent_id: 1,
        status: 2
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :menu_type)
    assert Keyword.has_key?(changeset.errors, :status)
  end

  test "notice changeset validates notice type and status" do
    changeset =
      SysNotice.changeset(%SysNotice{}, %{
        notice_title: "维护",
        notice_type: 9,
        notice_content: "内容",
        status: 2
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :notice_type)
    assert Keyword.has_key?(changeset.errors, :status)
  end

  test "log maps omit database-only deletion fields" do
    login = %SysLoginInfo{
      info_id: "018f2a7e-5d3c-7b01-8a11-000000000141",
      username: "admin",
      status: 1
    }

    operation = %SysOperationLog{
      operation_id: "018f2a7e-5d3c-7b01-8a11-000000000142",
      username: "admin",
      business_type: 1,
      request_method: 2,
      operator_type: 2,
      status: 1
    }

    login_map = KeystonePhoenix.Log.login_info_to_map(login)
    operation_map = KeystonePhoenix.Log.operation_log_to_map(operation)

    refute Map.has_key?(login_map, "deleted")
    refute Map.has_key?(operation_map, "deleted")
    assert login_map["logId"] == "018f2a7e-5d3c-7b01-8a11-000000000141"
    assert login_map["statusStr"] == "登录成功"
    assert operation_map["businessTypeStr"] == "添加"
    assert operation_map["requestMethod"] == "POST"
    assert operation_map["operatorTypeStr"] == "Web用户"
    assert operation_map["statusStr"] == "成功"
  end

  test "dictionary default values use the frontend's numeric contract" do
    changeset =
      DictData.changeset(%DictData{}, %{
        dict_type: "common.yesOrNo",
        dict_label: "是",
        dict_value: 1,
        dict_sort: 1,
        is_default: "1",
        status: 1
      })

    assert changeset.valid?
    assert Dictionary.dict_data_to_map(Ecto.Changeset.apply_changes(changeset))["isDefault"] == 1
  end
end
