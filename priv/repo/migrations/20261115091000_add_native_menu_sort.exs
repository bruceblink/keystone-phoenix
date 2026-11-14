defmodule KeystonePhoenix.Repo.Migrations.AddNativeMenuSort do
  use Ecto.Migration

  @moduledoc "为 Native HTTP 资源增加持久化的菜单排序值。"

  def up do
    execute("ALTER TABLE sys_menu ADD COLUMN IF NOT EXISTS menu_sort integer NOT NULL DEFAULT 0")
  end

  def down do
    execute("ALTER TABLE sys_menu DROP COLUMN IF EXISTS menu_sort")
  end
end
