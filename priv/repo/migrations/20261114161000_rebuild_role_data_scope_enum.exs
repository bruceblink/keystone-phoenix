defmodule KeystonePhoenix.Repo.Migrations.RebuildRoleDataScopeEnum do
  use Ecto.Migration

  @moduledoc """
  将角色数据范围一次性转换为跨项目统一的规范字符串。

  旧整数只在迁移表达式中出现；迁移完成后数据库、领域层和接口只保存范围名称。
  """

  def up do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'sys_role'
          AND column_name = 'data_scope'
          AND data_type IN ('smallint', 'integer')
      ) THEN
        ALTER TABLE sys_role
        ALTER COLUMN data_scope TYPE varchar(32)
        USING CASE data_scope
          WHEN 1 THEN 'ALL'
          WHEN 2 THEN 'CUSTOM'
          WHEN 3 THEN 'DEPARTMENT'
          WHEN 4 THEN 'DEPARTMENT_AND_CHILDREN'
          WHEN 5 THEN 'SELF'
          ELSE NULL
        END;
      END IF;
    END $$;
    """)

    execute("""
    ALTER TABLE sys_role
    ALTER COLUMN data_scope SET DEFAULT 'ALL',
    ALTER COLUMN data_scope SET NOT NULL
    """)
  end

  def down do
    execute("""
    ALTER TABLE sys_role
    ALTER COLUMN data_scope TYPE smallint
    USING CASE data_scope
      WHEN 'ALL' THEN 1
      WHEN 'CUSTOM' THEN 2
      WHEN 'DEPARTMENT' THEN 3
      WHEN 'DEPARTMENT_AND_CHILDREN' THEN 4
      WHEN 'SELF' THEN 5
      ELSE 1
    END
    """)

    execute("ALTER TABLE sys_role ALTER COLUMN data_scope SET DEFAULT 1")
  end
end
