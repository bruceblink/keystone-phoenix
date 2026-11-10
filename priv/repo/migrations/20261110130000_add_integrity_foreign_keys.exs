defmodule KeystonePhoenix.Repo.Migrations.AddIntegrityForeignKeys do
  use Ecto.Migration

  @moduledoc """
  Adds foreign keys after checking existing rows for orphaned references.

  Soft-deleted records remain valid references. Physical deletion of optional
  records clears the reference with `SET NULL`; role-menu and dictionary
  references reject physical deletion.

  Audit log actor fields that use the sentinel value `0` are not constrained in
  this migration. Operation log actor and department fields also keep their
  existing sentinel semantics.
  """

  @constraints [
    {:sys_role_menu, :role_id, :sys_role, :role_id, :restrict},
    {:sys_role_menu, :menu_id, :sys_menu, :menu_id, :restrict},
    {:sys_dict_data, :dict_type, :sys_dict_type, :dict_type, :restrict},
    {:sys_job_log, :job_id, :sys_job, :job_id, :nilify_all},
    {:sys_user, :post_id, :sys_post, :post_id, :nilify_all},
    {:sys_user, :role_id, :sys_role, :role_id, :nilify_all},
    {:sys_user, :dept_id, :sys_dept, :dept_id, :nilify_all},
    {:sys_dept, :leader_id, :sys_user, :user_id, :nilify_all}
  ]

  @audit_tables ~w(
    sys_dict_type
    sys_dict_data
    sys_config
    sys_user
    sys_dept
    sys_post
    sys_role
    sys_menu
    sys_notice
    sys_job
  )

  def up do
    check_orphans()

    Enum.each(@constraints, fn {table, column, target, target_column, on_delete} ->
      execute("""
      ALTER TABLE #{table}
      ADD CONSTRAINT #{constraint_name(table, column)}
      FOREIGN KEY (#{column}) REFERENCES #{target} (#{target_column})
      ON DELETE #{on_delete_sql(on_delete)}
      """)
    end)

    Enum.each(@audit_tables, fn table ->
      Enum.each(~w(creator_id updater_id), fn column ->
        execute("""
        ALTER TABLE #{table}
        ADD CONSTRAINT #{constraint_name(table, column)}
        FOREIGN KEY (#{column}) REFERENCES sys_user (user_id)
        ON DELETE SET NULL
        """)
      end)
    end)
  end

  def down do
    Enum.each(@audit_tables, fn table ->
      Enum.each(~w(creator_id updater_id), fn column ->
        execute("ALTER TABLE #{table} DROP CONSTRAINT #{constraint_name(table, column)}")
      end)
    end)

    Enum.each(@constraints, fn {table, column, _target, _target_column, _on_delete} ->
      execute("ALTER TABLE #{table} DROP CONSTRAINT #{constraint_name(table, column)}")
    end)
  end

  defp check_orphans do
    Enum.each(@constraints, fn {table, column, target, target_column, _on_delete} ->
      execute("""
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM #{table} source
          LEFT JOIN #{target} target ON target.#{target_column} = source.#{column}
          WHERE source.#{column} IS NOT NULL AND target.#{target_column} IS NULL
        ) THEN
          RAISE EXCEPTION 'cannot add foreign key for #{table}.#{column}: orphaned rows exist';
        END IF;
      END $$;
      """)
    end)

    Enum.each(@audit_tables, fn table ->
      Enum.each(~w(creator_id updater_id), fn column ->
        execute("""
        DO $$
        BEGIN
          IF EXISTS (
            SELECT 1
            FROM #{table} source
            LEFT JOIN sys_user actor ON actor.user_id = source.#{column}
            WHERE source.#{column} IS NOT NULL
              AND source.#{column} <> 0
              AND actor.user_id IS NULL
          ) THEN
            RAISE EXCEPTION 'cannot add foreign key for #{table}.#{column}: orphaned rows exist';
          END IF;
        END $$;
        """)
      end)
    end)
  end

  defp constraint_name(table, column), do: "#{table}_#{column}_fk"

  defp on_delete_sql(:restrict), do: "RESTRICT"
  defp on_delete_sql(:nilify_all), do: "SET NULL"
end
