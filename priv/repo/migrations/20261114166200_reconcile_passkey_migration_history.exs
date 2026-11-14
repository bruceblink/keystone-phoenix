defmodule KeystonePhoenix.Repo.Migrations.ReconcilePasskeyMigrationHistory do
  use Ecto.Migration

  @moduledoc "恢复已发布的 20261114166200 迁移编号；实际 Passkey 表结构由后续 20261114167000 建立。"

  # 保留已经写入环境的迁移编号，避免新环境和升级环境出现迁移清单断档。
  def up, do: :ok
  def down, do: :ok
end
