defmodule KeystonePhoenix.Repo.Migrations.AddNativeConfigEnabled do
  use Ecto.Migration

  @moduledoc "为 Native 系统配置资源增加启用状态字段。"

  def up do
    execute(
      "ALTER TABLE sys_config ADD COLUMN IF NOT EXISTS enabled boolean NOT NULL DEFAULT true"
    )
  end

  def down do
    execute("ALTER TABLE sys_config DROP COLUMN IF EXISTS enabled")
  end
end
