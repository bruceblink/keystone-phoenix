defmodule KeystonePhoenix.Repo.Migrations.CreateSystemManagementTables do
  use Ecto.Migration

  def change do
    create table(:sys_dept, primary_key: false) do
      add :dept_id, :bigserial, primary_key: true
      add :parent_id, :bigint, null: false, default: 0
      add :ancestors, :text, null: false, default: "0"
      add :dept_name, :string, size: 64, null: false, default: ""
      add :order_num, :integer, null: false, default: 0
      add :leader_id, :bigint
      add :leader_name, :string, size: 64
      add :phone, :string, size: 16
      add :email, :string, size: 128
      add :status, :smallint, null: false, default: 1
      add :creator_id, :bigint
      add :updater_id, :bigint
      add :deleted, :boolean, null: false, default: false

      timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
    end

    create index(:sys_dept, [:parent_id], name: :sys_dept_parent_id_index)
    create index(:sys_dept, [:status], name: :sys_dept_status_index)

    create table(:sys_post, primary_key: false) do
      add :post_id, :bigserial, primary_key: true
      add :post_code, :string, size: 64, null: false
      add :post_name, :string, size: 64, null: false
      add :post_sort, :integer, null: false, default: 0
      add :status, :smallint, null: false, default: 1
      add :remark, :string, size: 512
      add :creator_id, :bigint
      add :updater_id, :bigint
      add :deleted, :boolean, null: false, default: false

      timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
    end

    create unique_index(:sys_post, [:post_code], name: :sys_post_post_code_unique_index)
    create index(:sys_post, [:status], name: :sys_post_status_index)

    create table(:sys_role, primary_key: false) do
      add :role_id, :bigserial, primary_key: true
      add :role_name, :string, size: 32, null: false
      add :role_key, :string, size: 128, null: false
      add :role_sort, :integer, null: false, default: 0
      add :data_scope, :smallint, null: false, default: 1
      add :dept_id_set, :string, size: 1024, null: false, default: ""
      add :status, :smallint, null: false, default: 1
      add :creator_id, :bigint
      add :updater_id, :bigint
      add :remark, :string, size: 512
      add :deleted, :boolean, null: false, default: false

      timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
    end

    create unique_index(:sys_role, [:role_key], name: :sys_role_role_key_unique_index)
    create index(:sys_role, [:status], name: :sys_role_status_index)

    create table(:sys_menu, primary_key: false) do
      add :menu_id, :bigserial, primary_key: true
      add :menu_name, :string, size: 64, null: false
      add :menu_type, :smallint, null: false, default: 0
      add :router_name, :string, size: 255, null: false, default: ""
      add :parent_id, :bigint, null: false, default: 0
      add :path, :string, size: 255
      add :is_button, :boolean, null: false, default: false
      add :permission, :string, size: 128
      add :meta_info, :string, size: 1024, null: false, default: "{}"
      add :status, :smallint, null: false, default: 1
      add :remark, :string, size: 256, default: ""
      add :creator_id, :bigint
      add :updater_id, :bigint
      add :deleted, :boolean, null: false, default: false

      timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
    end

    create index(:sys_menu, [:parent_id], name: :sys_menu_parent_id_index)
    create index(:sys_menu, [:status], name: :sys_menu_status_index)

    create table(:sys_role_menu, primary_key: false) do
      add :role_id, :bigint, null: false
      add :menu_id, :bigint, null: false
    end

    create unique_index(:sys_role_menu, [:role_id, :menu_id],
             name: :sys_role_menu_role_id_menu_id_unique_index
           )
  end
end
