defmodule KeystonePhoenix.Repo.Migrations.AddManagementCodeTriggers do
  use Ecto.Migration

  @moduledoc "为绕过 Ecto changeset 的旧式写入生成确定性的编码。"

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION keystone_fill_dept_code() RETURNS trigger AS $$
    BEGIN
      IF NEW.dept_code IS NULL OR btrim(NEW.dept_code) = '' THEN
        NEW.dept_code := 'dept-' || replace(NEW.dept_id::text, '-', '');
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE OR REPLACE FUNCTION keystone_fill_menu_code() RETURNS trigger AS $$
    BEGIN
      IF NEW.menu_code IS NULL OR btrim(NEW.menu_code) = '' THEN
        NEW.menu_code := 'menu-' || replace(NEW.menu_id::text, '-', '');
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("DROP TRIGGER IF EXISTS keystone_fill_dept_code_trigger ON sys_dept")
    execute("DROP TRIGGER IF EXISTS keystone_fill_menu_code_trigger ON sys_menu")

    execute(
      "CREATE TRIGGER keystone_fill_dept_code_trigger BEFORE INSERT OR UPDATE ON sys_dept FOR EACH ROW EXECUTE FUNCTION keystone_fill_dept_code()"
    )

    execute(
      "CREATE TRIGGER keystone_fill_menu_code_trigger BEFORE INSERT OR UPDATE ON sys_menu FOR EACH ROW EXECUTE FUNCTION keystone_fill_menu_code()"
    )
  end

  def down do
    execute("DROP TRIGGER IF EXISTS keystone_fill_menu_code_trigger ON sys_menu")
    execute("DROP TRIGGER IF EXISTS keystone_fill_dept_code_trigger ON sys_dept")
    execute("DROP FUNCTION IF EXISTS keystone_fill_menu_code()")
    execute("DROP FUNCTION IF EXISTS keystone_fill_dept_code()")
  end
end
