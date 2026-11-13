defmodule KeystonePhoenix.Menu.SysMenu do
  @moduledoc "PostgreSQL schema for a Keystone menu or permission."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:menu_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_menu" do
    field :menu_name, :string
    field :menu_type, :integer, default: 0
    field :router_name, :string, default: ""
    field :parent_id, :binary_id
    field :path, :string
    field :is_button, :boolean, default: false
    field :meta_info, :string, default: "{}"
    field :status, :integer, default: 1
    field :remark, :string, default: ""
    field :creator_id, :binary_id
    field :updater_id, :binary_id
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  def changeset(menu, attrs) do
    menu
    |> cast(attrs, [
      :menu_name,
      :menu_type,
      :router_name,
      :parent_id,
      :path,
      :is_button,
      :meta_info,
      :status,
      :remark
    ])
    |> put_new_id()
    |> validate_required([:menu_name, :menu_type, :status])
    |> validate_length(:menu_name, max: 64)
    |> validate_length(:router_name, max: 255)
    |> validate_length(:path, max: 255)
    |> validate_length(:meta_info, max: 1024)
    |> validate_length(:remark, max: 256)
    |> validate_inclusion(:menu_type, [0, 1, 2, 3, 4])
    |> validate_inclusion(:status, [0, 1])
  end

  # 新菜单 ID 使用 UUIDv7，根菜单 parent_id 使用 NULL。
  defp put_new_id(changeset) do
    if get_field(changeset, :menu_id),
      do: changeset,
      else: put_change(changeset, :menu_id, KeystonePhoenix.Identity.v7())
  end
end
