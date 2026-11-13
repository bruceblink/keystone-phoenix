defmodule KeystonePhoenix.Repo.Migrations.RebuildPermissionIdsAsUuid do
  use Ecto.Migration

  alias KeystonePhoenix.Authz.PermissionCatalog
  alias KeystonePhoenix.Identity

  @moduledoc """
  将权限目录和权限关联表一次性重建为 UUID 主键。

  本迁移允许破坏性更新。权限关联根据新的目录重新生成，不读取菜单字段，
  以保证菜单展示数据不能成为授权来源。`domain` 仅保留为目录元数据，不参与
  权限计算。角色主键仍由后续主键迁移处理。
  """

  def up do
    unless uuid_catalog_ready?() do
      rebuild_tables()
      seed_permissions()
      grant_system_role()
    end
  end

  def down do
    raise "permission UUID migration is irreversible"
  end

  defp rebuild_tables do
    # 先删除旧关联，避免旧 bigint 外键阻止权限主表重建。
    execute(
      "DROP TABLE IF EXISTS sys_menu_permission, sys_role_permission, sys_permission CASCADE"
    )

    create table(:sys_permission, primary_key: false) do
      add :permission_id, :uuid, primary_key: true, null: false
      add :permission, :string, size: 128, null: false
      add :resource, :string, size: 64, null: false
      add :domain, :string, size: 64, null: false
      add :action, :string, size: 64, null: false
      add :description, :string, size: 256, null: false, default: ""
      add :risk, :string, size: 16, null: false, default: "low"
      add :deprecated, :boolean, null: false, default: false
      add :status, :smallint, null: false, default: 1
      add :version, :integer, null: false, default: 1

      timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
    end

    create unique_index(:sys_permission, [:permission],
             name: :sys_permission_permission_unique_index
           )

    create index(:sys_permission, [:resource, :domain, :action],
             name: :sys_permission_action_index
           )

    create index(:sys_permission, [:permission, :version],
             name: :sys_permission_permission_version_index
           )

    create table(:sys_role_permission, primary_key: false) do
      add :role_id,
          references(:sys_role, column: :role_id, type: :bigint, on_delete: :delete_all),
          null: false

      add :permission_id,
          references(:sys_permission,
            column: :permission_id,
            type: :uuid,
            on_delete: :delete_all
          ),
          null: false
    end

    create unique_index(:sys_role_permission, [:role_id, :permission_id],
             name: :sys_role_permission_role_id_permission_id_unique_index
           )

    create table(:sys_menu_permission, primary_key: false) do
      add :menu_id,
          references(:sys_menu, column: :menu_id, type: :bigint, on_delete: :delete_all),
          null: false

      add :permission_id,
          references(:sys_permission,
            column: :permission_id,
            type: :uuid,
            on_delete: :delete_all
          ),
          null: false
    end

    create unique_index(:sys_menu_permission, [:menu_id, :permission_id],
             name: :sys_menu_permission_menu_id_permission_id_unique_index
           )
  end

  defp seed_permissions do
    values =
      PermissionCatalog.entries()
      |> Enum.map(fn entry ->
        [
          Identity.permission_id(entry.permission),
          entry.permission,
          entry.resource,
          entry.domain,
          entry.action,
          entry.description,
          Atom.to_string(entry.risk),
          entry.deprecated
        ]
        |> Enum.map(&sql_literal/1)
        |> Kernel.++(["1", "1", "CURRENT_TIMESTAMP", "CURRENT_TIMESTAMP"])
        |> Enum.join(", ")
        |> then(&("(" <> &1 <> ")"))
      end)
      |> Enum.join(",\n")

    execute("""
    INSERT INTO sys_permission
      (permission_id, permission, resource, domain, action, description, risk, deprecated,
       status, version, create_time, update_time)
    VALUES
      #{values}
    ON CONFLICT (permission_id) DO NOTHING
    """)
  end

  defp grant_system_role do
    # 只按角色自身的稳定业务键授予权限，不读取菜单字段或固定整数角色 ID。
    execute("""
    INSERT INTO sys_role_permission (role_id, permission_id)
    SELECT role.role_id, permission.permission_id
    FROM sys_role role
    CROSS JOIN sys_permission permission
    WHERE role.role_key = 'admin' AND role.deleted = false AND permission.status = 1
    ON CONFLICT (role_id, permission_id) DO NOTHING
    """)
  end

  defp uuid_catalog_ready? do
    %{rows: [[count]]} =
      repo().query!("""
      SELECT COUNT(*)
      FROM information_schema.columns
      WHERE table_schema = current_schema()
        AND column_name = 'permission_id'
        AND data_type = 'uuid'
        AND table_name IN ('sys_permission', 'sys_role_permission', 'sys_menu_permission')
      """)

    count == 3 and indexes_ready?() and catalog_seed_ready?()
  end

  defp indexes_ready? do
    %{rows: [[count]]} =
      repo().query!("""
      SELECT COUNT(*)
      FROM pg_indexes
      WHERE schemaname = current_schema()
        AND indexname IN (
          'sys_permission_permission_unique_index',
          'sys_permission_action_index',
          'sys_permission_permission_version_index',
          'sys_role_permission_role_id_permission_id_unique_index',
          'sys_menu_permission_menu_id_permission_id_unique_index'
        )
      """)

    count == 5
  end

  defp catalog_seed_ready? do
    expected_count = length(PermissionCatalog.entries())
    sentinel = Identity.permission_id("permission:read")

    %{rows: [[count, sentinel_count]]} =
      repo().query!(
        """
        SELECT COUNT(*), COUNT(*) FILTER (WHERE permission_id = $1::uuid)
        FROM sys_permission
        """,
        [sentinel]
      )

    count == expected_count and sentinel_count == 1
  end

  defp sql_literal(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "''") <> "'"
  end

  defp sql_literal(value) when is_boolean(value), do: if(value, do: "TRUE", else: "FALSE")

  defp sql_literal(value),
    do: raise(ArgumentError, "unsupported catalog SQL value: #{inspect(value)}")
end
