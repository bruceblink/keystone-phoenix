defmodule KeystonePhoenix.Repo.Migrations.RemoveIsAdminBypass do
  use Ecto.Migration

  @moduledoc """
  删除旧用户表中的管理员旁路字段。

  管理员能力只由角色绑定的 `permission:manage` 授予。迁移保持可重复执行，
  既有数据库只删除字段，不修改已经执行的历史迁移。
  """

  def up do
    execute("ALTER TABLE sys_user DROP COLUMN IF EXISTS is_admin")
  end

  def down do
    # clean-break 版本不恢复管理员旁路字段；回滚边界是恢复数据库备份。
    :ok
  end
end
