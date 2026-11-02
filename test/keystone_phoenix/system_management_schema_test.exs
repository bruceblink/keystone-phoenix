defmodule KeystonePhoenix.SystemManagementSchemaTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Notice.SysNotice
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
end
