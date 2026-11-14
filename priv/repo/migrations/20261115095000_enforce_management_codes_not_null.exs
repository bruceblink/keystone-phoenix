defmodule KeystonePhoenix.Repo.Migrations.EnforceManagementCodesNotNull do
  use Ecto.Migration

  @moduledoc "安装旧式写入触发器后，收紧部门编码和菜单编码的非空约束。"

  def up do
    execute("""
    UPDATE sys_dept
    SET dept_code = 'dept-' || replace(dept_id::text, '-', '')
    WHERE dept_code IS NULL OR btrim(dept_code) = ''
    """)

    execute("""
    UPDATE sys_menu
    SET menu_code = 'menu-' || replace(menu_id::text, '-', '')
    WHERE menu_code IS NULL OR btrim(menu_code) = ''
    """)

    execute("ALTER TABLE sys_dept ALTER COLUMN dept_code SET NOT NULL")
    execute("ALTER TABLE sys_menu ALTER COLUMN menu_code SET NOT NULL")
  end

  def down do
    execute("ALTER TABLE sys_menu ALTER COLUMN menu_code DROP NOT NULL")
    execute("ALTER TABLE sys_dept ALTER COLUMN dept_code DROP NOT NULL")
  end
end
