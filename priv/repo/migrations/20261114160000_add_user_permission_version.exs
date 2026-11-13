defmodule KeystonePhoenix.Repo.Migrations.AddUserPermissionVersion do
  use Ecto.Migration

  @moduledoc "为用户增加授权版本，用于立即失效旧访问令牌。"

  def change do
    alter table(:sys_user) do
      add :permission_version, :bigint, null: false, default: 1
    end
  end
end
