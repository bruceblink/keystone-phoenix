defmodule KeystonePhoenix.Notification.SysNotification do
  @moduledoc "PostgreSQL schema for a private user notification."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_user_notification" do
    field :user_id, :binary_id
    field :type, :string
    field :title, :string
    field :content, :string
    field :created_at, :utc_datetime_usec
    field :read_at, :utc_datetime_usec
  end

  @doc "验证通知的所有者、类型和展示内容。"
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:id, :user_id, :type, :title, :content, :created_at, :read_at])
    |> validate_required([:id, :user_id, :type, :title, :content, :created_at])
    |> validate_length(:type, max: 64)
    |> validate_length(:title, max: 255)
    |> foreign_key_constraint(:user_id)
  end
end
