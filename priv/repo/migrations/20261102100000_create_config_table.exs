defmodule KeystonePhoenix.Repo.Migrations.CreateConfigTable do
  use Ecto.Migration

  def change do
    create table(:sys_config, primary_key: false) do
      add :config_id, :bigserial, primary_key: true
      add :config_name, :string, size: 128, null: false, default: ""
      add :config_key, :string, size: 128, null: false, default: ""
      add :config_options, :string, size: 1024, null: false, default: ""
      add :config_value, :string, size: 256, null: false, default: ""
      add :is_allow_change, :boolean, null: false, default: true
      add :creator_id, :bigint
      add :updater_id, :bigint
      add :remark, :string, size: 128
      add :deleted, :boolean, null: false, default: false

      timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
    end

    create unique_index(:sys_config, [:config_key], name: :sys_config_config_key_unique_index)
  end
end
