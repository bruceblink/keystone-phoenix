defmodule KeystonePhoenix.Repo.Migrations.CreateUserNotifications do
  use Ecto.Migration

  @moduledoc "为用户创建独立的站内通知收件箱。"

  def up do
    create_if_not_exists table(:sys_user_notification, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id,
          references(:sys_user, column: :user_id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :type, :string, size: 64, null: false
      add :title, :string, size: 255, null: false
      add :content, :text, null: false
      add :created_at, :utc_datetime_usec, null: false, default: fragment("CURRENT_TIMESTAMP")
      add :read_at, :utc_datetime_usec
    end

    create_if_not_exists index(:sys_user_notification, [:user_id, :created_at, :id],
                           name: :sys_user_notification_owner_created_index
                         )

    create_if_not_exists index(:sys_user_notification, [:user_id],
                           where: "read_at IS NULL",
                           name: :sys_user_notification_owner_unread_index
                         )
  end

  def down do
    drop_if_exists index(:sys_user_notification, [:user_id],
                     name: :sys_user_notification_owner_unread_index
                   )

    drop_if_exists index(:sys_user_notification, [:user_id, :created_at, :id],
                     name: :sys_user_notification_owner_created_index
                   )

    drop_if_exists table(:sys_user_notification)
  end
end
