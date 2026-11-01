defmodule KeystonePhoenix.Repo.Migrations.CreateDictionaryTables do
  use Ecto.Migration

  def change do
    create table(:sys_dict_type, primary_key: false) do
      add :dict_id, :bigserial, primary_key: true
      add :dict_name, :string, size: 100, null: false, default: ""
      add :dict_type, :string, size: 100, null: false, default: ""
      add :status, :smallint, null: false, default: 1
      add :remark, :string, size: 500
      add :creator_id, :bigint
      add :updater_id, :bigint
      add :deleted, :boolean, null: false, default: false

      timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
    end

    create unique_index(:sys_dict_type, [:dict_type], name: :sys_dict_type_dict_type_unique_index)

    create table(:sys_dict_data, primary_key: false) do
      add :dict_code, :bigserial, primary_key: true
      add :dict_type, :string, size: 100, null: false, default: ""
      add :dict_label, :string, size: 100, null: false, default: ""
      add :dict_value, :integer, null: false, default: 0
      add :dict_sort, :integer, null: false, default: 0
      add :is_default, :boolean, null: false, default: false
      add :css_class, :string, size: 100
      add :list_class, :string, size: 100
      add :status, :smallint, null: false, default: 1
      add :remark, :string, size: 500
      add :creator_id, :bigint
      add :updater_id, :bigint
      add :deleted, :boolean, null: false, default: false

      timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
    end

    create index(:sys_dict_data, [:dict_type], name: :sys_dict_data_dict_type_index)
  end
end
