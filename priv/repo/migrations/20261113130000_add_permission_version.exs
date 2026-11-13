defmodule KeystonePhoenix.Repo.Migrations.AddPermissionVersion do
  use Ecto.Migration

  @moduledoc "Adds a monotonic version to canonical permission definitions."

  def up do
    alter table(:sys_permission) do
      add :version, :integer, null: false, default: 1
    end

    create index(:sys_permission, [:permission, :version],
             name: :sys_permission_permission_version_index
           )
  end

  def down do
    drop index(:sys_permission, [:permission, :version],
           name: :sys_permission_permission_version_index
         )

    alter table(:sys_permission) do
      remove :version
    end
  end
end
