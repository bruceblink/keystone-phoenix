defmodule KeystonePhoenix.Repo.Migrations.CreateNoticeTable do
  use Ecto.Migration

  def change do
    create table(:sys_notice, primary_key: false) do
      add :notice_id, :bigserial, primary_key: true
      add :notice_title, :string, size: 64, null: false
      add :notice_type, :smallint, null: false
      add :notice_content, :text
      add :status, :smallint, null: false, default: 1
      add :creator_id, :bigint
      add :updater_id, :bigint
      add :remark, :string, size: 255, null: false, default: ""
      add :deleted, :boolean, null: false, default: false

      timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
    end

    create index(:sys_notice, [:notice_type], name: :sys_notice_notice_type_index)
    create index(:sys_notice, [:status], name: :sys_notice_status_index)
  end
end
