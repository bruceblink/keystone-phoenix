defmodule KeystonePhoenix.Authz.PermissionUuidMigrationTest do
  @moduledoc """
  验证权限目录及两个关联表使用 PostgreSQL UUID，并检查固定 UUIDv5 向量。
  """

  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Authz.{PermissionCatalog, SysPermission}
  alias KeystonePhoenix.Identity

  test "permission IDs use UUID columns and the fixed catalog vector" do
    column_types =
      Repo.query!("""
      SELECT table_name, data_type
      FROM information_schema.columns
      WHERE table_schema = current_schema()
        AND column_name = 'permission_id'
        AND table_name IN ('sys_permission', 'sys_role_permission', 'sys_menu_permission')
      ORDER BY table_name
      """).rows

    assert column_types == [
             ["sys_menu_permission", "uuid"],
             ["sys_permission", "uuid"],
             ["sys_role_permission", "uuid"]
           ]

    assert Repo.aggregate(SysPermission, :count, :permission_id) ==
             length(PermissionCatalog.entries())

    assert Repo.exists?(
             from permission in SysPermission,
               where:
                 permission.permission == "permission:read" and
                   permission.permission_id == ^Identity.permission_id("permission:read")
           )

    assert Identity.permission_id("user:read") ==
             "950c8856-7230-5a63-937f-472185c3a8c4"
  end
end
