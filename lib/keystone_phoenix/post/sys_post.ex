defmodule KeystonePhoenix.Post.SysPost do
  @moduledoc "PostgreSQL schema for a Keystone post."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:post_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sys_post" do
    field :post_code, :string
    field :post_name, :string
    field :post_sort, :integer, default: 0
    field :status, :integer, default: 1
    field :remark, :string
    field :creator_id, :integer
    field :updater_id, :integer
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:post_code, :post_name, :post_sort, :status, :remark])
    |> validate_required([:post_code, :post_name, :post_sort, :status])
    |> validate_length(:post_code, max: 64)
    |> validate_length(:post_name, max: 64)
    |> validate_length(:remark, max: 512)
    |> validate_number(:post_sort, greater_than_or_equal_to: 0)
    |> validate_inclusion(:status, [0, 1])
    |> unique_constraint(:post_code, name: :sys_post_post_code_unique_index)
  end
end
