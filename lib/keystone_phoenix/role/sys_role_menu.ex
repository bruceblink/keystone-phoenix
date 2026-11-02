defmodule KeystonePhoenix.Role.SysRoleMenu do
  @moduledoc "PostgreSQL schema for role to menu permissions."

  use Ecto.Schema

  @primary_key false

  schema "sys_role_menu" do
    field :role_id, :integer, primary_key: true
    field :menu_id, :integer, primary_key: true
  end
end
