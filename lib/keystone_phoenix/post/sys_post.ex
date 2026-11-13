defmodule KeystonePhoenix.Post.SysPost do
  @moduledoc "PostgreSQL schema for a Keystone post."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:post_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_post" do
    field :post_code, :string
    field :post_name, :string
    field :post_sort, :integer, default: 0
    field :status, :integer, default: 1
    field :remark, :string
    field :creator_id, :binary_id
    field :updater_id, :binary_id
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:post_code, :post_name, :post_sort, :status, :remark])
    |> put_new_id()
    |> validate_required([:post_code, :post_name, :post_sort, :status])
    |> validate_length(:post_code, max: 64)
    |> validate_length(:post_name, max: 64)
    |> validate_length(:remark, max: 512)
    |> validate_number(:post_sort, greater_than_or_equal_to: 0)
    |> validate_inclusion(:status, [0, 1])
    |> unique_constraint(:post_code, name: :sys_post_post_code_unique_index)
  end

  # 新岗位 ID 使用 UUIDv7，固定岗位种子由 seed 明确提供 UUIDv5。
  defp put_new_id(changeset) do
    if get_field(changeset, :post_id),
      do: changeset,
      else: put_change(changeset, :post_id, KeystonePhoenix.Identity.v7())
  end
end
