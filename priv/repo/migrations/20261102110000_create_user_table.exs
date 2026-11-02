defmodule KeystonePhoenix.Repo.Migrations.CreateUserTable do
  use Ecto.Migration

  def change do
    create table(:sys_user, primary_key: false) do
      add :user_id, :bigserial, primary_key: true
      add :post_id, :bigint
      add :role_id, :bigint
      add :dept_id, :bigint
      add :username, :string, size: 64, null: false, default: ""
      add :nickname, :string, size: 32, null: false, default: ""
      add :user_type, :smallint, default: 0
      add :email, :string, size: 128, default: ""
      add :phone_number, :string, size: 18, default: ""
      add :sex, :smallint, default: 2
      add :avatar, :string, size: 512, default: ""
      add :password, :string, size: 128, null: false, default: ""
      add :status, :smallint, null: false, default: 1
      add :login_ip, :string, size: 128, default: ""
      add :login_date, :utc_datetime_usec
      add :is_admin, :boolean, null: false, default: false
      add :external_subject, :string, size: 128
      add :external_user_id, :string, size: 128
      add :creator_id, :bigint
      add :updater_id, :bigint
      add :remark, :string, size: 512
      add :deleted, :boolean, null: false, default: false

      timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
    end

    create unique_index(:sys_user, [:username], name: :sys_user_username_unique_index)

    create unique_index(:sys_user, [:external_subject],
             name: :sys_user_external_subject_unique_index
           )

    create index(:sys_user, [:dept_id], name: :sys_user_dept_id_index)
    create index(:sys_user, [:status], name: :sys_user_status_index)
  end
end
