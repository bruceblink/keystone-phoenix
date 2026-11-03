defmodule KeystonePhoenix.User.SysUser do
  @moduledoc "PostgreSQL schema for a Keystone system user."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:user_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sys_user" do
    field :post_id, :integer
    field :role_id, :integer
    field :dept_id, :integer
    field :username, :string
    field :nickname, :string, default: ""
    field :user_type, :integer, default: 0
    field :email, :string, default: ""
    field :phone_number, :string, default: ""
    field :sex, :integer, default: 2
    field :avatar, :string, default: ""
    field :password, :string
    field :status, :integer, default: 1
    field :login_ip, :string, default: ""
    field :login_date, :utc_datetime_usec
    field :is_admin, :boolean, default: false
    field :external_subject, :string
    field :external_user_id, :string
    field :creator_id, :integer
    field :updater_id, :integer
    field :remark, :string
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  @user_fields [
    :post_id,
    :role_id,
    :dept_id,
    :username,
    :nickname,
    :email,
    :phone_number,
    :sex,
    :avatar,
    :status,
    :remark
  ]

  @password_pattern ~r/^(?!\s)(?!.*\s$)(?=.*[A-Za-z])(?=.*\d)(?=.*[^A-Za-z\d\s]).*$/

  @doc "Validates fields accepted when an administrator creates a user."
  def create_changeset(user, attrs) do
    user
    |> cast(attrs, @user_fields ++ [:password])
    |> validate_required([:username, :password])
    |> validate_user_fields()
    |> validate_password()
    |> update_change(:password, &Bcrypt.hash_pwd_salt/1)
    |> unique_constraint(:username, name: :sys_user_username_unique_index)
  end

  @doc "Validates fields accepted when an administrator updates a user."
  def update_changeset(user, attrs) do
    user
    |> cast(attrs, @user_fields)
    |> validate_required([:username])
    |> validate_user_fields()
    |> unique_constraint(:username, name: :sys_user_username_unique_index)
  end

  @doc "Validates and hashes a replacement password."
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password()
    |> update_change(:password, &Bcrypt.hash_pwd_salt/1)
  end

  defp validate_user_fields(changeset) do
    changeset
    |> validate_length(:username, max: 64)
    |> validate_format(:username, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/,
      message: "用户名只允许字母、数字和下划线，且首字符不能为数字"
    )
    |> validate_length(:nickname, max: 32)
    |> validate_length(:email, max: 128)
    |> validate_format(:email, ~r/^$|^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "邮箱格式不正确")
    |> validate_length(:phone_number, max: 18)
    |> validate_inclusion(:sex, [0, 1, 2])
    |> validate_length(:avatar, max: 512)
    |> validate_inclusion(:status, [0, 1])
    |> validate_length(:remark, max: 512)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 8, max: 32)
    |> validate_format(:password, @password_pattern, message: "密码首尾不能包含空格，且必须包含字母、数字和特殊符号")
  end
end
