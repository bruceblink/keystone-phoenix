defmodule KeystonePhoenix.Repo.Migrations.ExpandExternalSubjectForOidcIssuer do
  use Ecto.Migration

  @moduledoc "为 OIDC 完整 issuer 和 subject 组合保留足够的映射长度。"

  def change do
    alter table(:sys_user) do
      modify :external_subject, :string, size: 512
    end
  end
end
