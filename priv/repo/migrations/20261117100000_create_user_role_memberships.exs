defmodule KeystonePhoenix.Repo.Migrations.CreateUserRoleMemberships do
  use Ecto.Migration

  @moduledoc """
  创建用户和角色的多对多关联表。

  旧的 `sys_user.role_id` 字段保留为兼容字段。本迁移只创建关联表并回填已有的
  单角色关系，不切换鉴权或用户写入路径。DDL 和回填都可以安全重复执行。
  """

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS sys_user_role (
      user_id uuid NOT NULL,
      role_id uuid NOT NULL,
      CONSTRAINT sys_user_role_pkey PRIMARY KEY (user_id, role_id),
      CONSTRAINT sys_user_role_user_id_fkey
        FOREIGN KEY (user_id) REFERENCES sys_user(user_id) ON DELETE CASCADE,
      CONSTRAINT sys_user_role_role_id_fkey
        FOREIGN KEY (role_id) REFERENCES sys_role(role_id) ON DELETE CASCADE
    )
    """)

    # 主键已经覆盖按用户查询，角色反向查询需要独立索引。
    execute("CREATE INDEX IF NOT EXISTS sys_user_role_role_id_index ON sys_user_role (role_id)")

    # 旧字段只回填非空关系；重复执行不会产生重复绑定。
    execute("""
    INSERT INTO sys_user_role (user_id, role_id)
    SELECT user_id, role_id
    FROM sys_user
    WHERE role_id IS NOT NULL
    ON CONFLICT (user_id, role_id) DO NOTHING
    """)

    ensure_backfill_consistency()
  end

  def down do
    execute("DROP TABLE IF EXISTS sys_user_role CASCADE")
  end

  defp ensure_backfill_consistency do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM sys_user user_row
        LEFT JOIN sys_user_role membership
          ON membership.user_id = user_row.user_id
         AND membership.role_id = user_row.role_id
        WHERE user_row.role_id IS NOT NULL
          AND membership.user_id IS NULL
      ) THEN
        RAISE EXCEPTION 'sys_user_role backfill is incomplete';
      END IF;
    END $$;
    """)
  end
end
