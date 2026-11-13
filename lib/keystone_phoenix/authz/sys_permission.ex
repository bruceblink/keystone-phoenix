defmodule KeystonePhoenix.Authz.SysPermission do
  @moduledoc """
  PostgreSQL 中的规范权限目录记录。

  `domain` 仅用于展示和筛选元数据，不参与权限计算。权限计算只使用目录中的
  `permission` 和固定 UUIDv5 主键。
  """

  use Ecto.Schema

  # 目录和自定义权限都必须由调用方显式提供 UUID，禁止回退到随机 UUIDv4。
  @primary_key {:permission_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_permission" do
    field :permission, :string
    field :resource, :string
    field :domain, :string
    field :action, :string
    field :description, :string, default: ""
    field :risk, :string, default: "low"
    field :deprecated, :boolean, default: false
    field :status, :integer, default: 1
    field :version, :integer, default: 1

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end
end
