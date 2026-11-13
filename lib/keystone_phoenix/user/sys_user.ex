defmodule KeystonePhoenix.User.SysUser do
  @moduledoc "PostgreSQL schema for a Keystone system user."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:user_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_user" do
    # 岗位表在后续身份切片迁移；本切片只改用户、角色和部门 ID。
    field :post_id, :integer
    field :role_id, :binary_id
    field :dept_id, :binary_id
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
    field :creator_id, :binary_id
    field :updater_id, :binary_id
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
    |> put_new_id()
    |> validate_required([:username, :password])
    |> validate_user_fields()
    |> validate_password()
    |> update_change(:password, &Bcrypt.hash_pwd_salt/1)
    |> unique_constraint(:username, name: :sys_user_username_unique_index)
  end

  # 新用户 ID 在应用层生成 UUIDv7，数据库只保存 UUID 的 16 字节值。
  defp put_new_id(changeset) do
    if Ecto.Changeset.get_field(changeset, :user_id),
      do: changeset,
      else: Ecto.Changeset.put_change(changeset, :user_id, KeystonePhoenix.Identity.v7())
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
    |> validate_avatar()
    |> validate_inclusion(:status, [0, 1])
    |> validate_length(:remark, max: 512)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 8, max: 32)
    |> validate_format(:password, @password_pattern, message: "密码首尾不能包含空格，且必须包含字母、数字和特殊符号")
  end

  defp validate_avatar(changeset) do
    validate_change(changeset, :avatar, fn :avatar, value ->
      if valid_avatar_reference?(value), do: [], else: [avatar: "头像地址无效"]
    end)
  end

  defp valid_avatar_reference?(value) when is_binary(value) do
    value = String.trim(value)

    value == "" or
      String.starts_with?(value, "/profile/") or
      valid_remote_avatar_url?(value)
  end

  defp valid_avatar_reference?(_value), do: false

  defp valid_remote_avatar_url?(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host != "" and not String.contains?(value, ["\r", "\n"])

      _ ->
        false
    end
  end
end
