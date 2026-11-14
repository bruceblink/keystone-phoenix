defmodule KeystonePhoenix.Repo.Migrations.AddNativeDepartmentMenuCodes do
  use Ecto.Migration

  @moduledoc "为 Native HTTP 资源增加持久化的部门编码和菜单编码。"

  def up do
    execute("ALTER TABLE sys_dept ADD COLUMN IF NOT EXISTS dept_code varchar(64)")
    execute("ALTER TABLE sys_menu ADD COLUMN IF NOT EXISTS menu_code varchar(64)")

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

    create_if_not_exists unique_index(:sys_dept, [:dept_code],
                           name: :sys_dept_dept_code_unique_index
                         )

    create_if_not_exists unique_index(:sys_menu, [:menu_code],
                           name: :sys_menu_menu_code_unique_index
                         )
  end

  def down do
    drop_if_exists index(:sys_menu, [:menu_code], name: :sys_menu_menu_code_unique_index)
    drop_if_exists index(:sys_dept, [:dept_code], name: :sys_dept_dept_code_unique_index)
    execute("ALTER TABLE sys_menu DROP COLUMN IF EXISTS menu_code")
    execute("ALTER TABLE sys_dept DROP COLUMN IF EXISTS dept_code")
  end
end
