defmodule KeystonePhoenix.User.SysUserRole do
  @moduledoc "用户和角色多对多关联表的 Ecto schema；阶段 A 只提供结构，不切换现有写入路径。"

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  schema "sys_user_role" do
    field :user_id, :binary_id, primary_key: true
    field :role_id, :binary_id, primary_key: true
  end

  @doc "校验一条关联记录，不改变现有用户角色写入逻辑。"
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:user_id, :role_id])
    |> validate_required([:user_id, :role_id])
  end
end
