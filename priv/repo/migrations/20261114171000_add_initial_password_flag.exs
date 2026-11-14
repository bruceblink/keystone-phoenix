defmodule KeystonePhoenix.Repo.Migrations.AddInitialPasswordFlag do
  use Ecto.Migration

  @moduledoc "Adds the initial password change flag used by the canonical auth endpoint."

  def up do
    alter table(:sys_user) do
      add :must_change_password, :boolean, null: false, default: false
    end
  end

  def down do
    alter table(:sys_user) do
      remove :must_change_password
    end
  end
end
