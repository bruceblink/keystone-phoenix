defmodule KeystonePhoenix.Authz.SysMenuPermission do
  @moduledoc "PostgreSQL schema for menu-to-capability associations."

  use Ecto.Schema

  @primary_key false

  schema "sys_menu_permission" do
    field :menu_id, :integer, primary_key: true
    field :permission_id, :binary_id, primary_key: true
  end
end
