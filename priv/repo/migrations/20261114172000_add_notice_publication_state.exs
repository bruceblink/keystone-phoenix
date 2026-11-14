defmodule KeystonePhoenix.Repo.Migrations.AddNoticePublicationState do
  use Ecto.Migration

  @moduledoc "Adds the publication state required by the Native notice API."

  def up do
    execute(
      "ALTER TABLE sys_notice ADD COLUMN IF NOT EXISTS published boolean NOT NULL DEFAULT false"
    )

    execute("ALTER TABLE sys_notice ADD COLUMN IF NOT EXISTS publish_at timestamptz")

    execute("""
    UPDATE sys_notice
    SET published = (status = 1),
        publish_at = CASE WHEN status = 1 THEN COALESCE(create_time, CURRENT_TIMESTAMP) ELSE NULL END
    WHERE published = false AND status = 1 AND publish_at IS NULL
    """)

    create_if_not_exists index(:sys_notice, [:published, :status, :publish_at],
                           name: :sys_notice_publication_index
                         )
  end

  def down do
    drop_if_exists index(:sys_notice, [:published, :status, :publish_at],
                     name: :sys_notice_publication_index
                   )

    execute("ALTER TABLE sys_notice DROP COLUMN IF EXISTS publish_at")
    execute("ALTER TABLE sys_notice DROP COLUMN IF EXISTS published")
  end
end
