defmodule KeystonePhoenix.Repo.Migrations.ChangeNoticeTypeToString do
  use Ecto.Migration

  @moduledoc "将公告类型改为 Native 使用的自由字符串。"

  def up do
    execute("""
    DO $notice_type_migration$
    DECLARE
      current_type text;
      current_limit integer;
      max_value_length integer;
      current_default text;
      current_nullable text;
    BEGIN
      SELECT data_type, character_maximum_length
        INTO current_type, current_limit
        FROM information_schema.columns
       WHERE table_schema = current_schema()
         AND table_name = 'sys_notice'
         AND column_name = 'notice_type';

      IF NOT FOUND THEN
        RAISE EXCEPTION 'sys_notice.notice_type is missing';
      END IF;

      IF current_type = 'smallint' THEN
        ALTER TABLE sys_notice ALTER COLUMN notice_type DROP DEFAULT;
        ALTER TABLE sys_notice ALTER COLUMN notice_type TYPE varchar(32)
          USING CASE notice_type
            WHEN 1 THEN 'notification'
            WHEN 2 THEN 'announcement'
            ELSE notice_type::text
          END;
      ELSIF current_type = 'integer' THEN
        ALTER TABLE sys_notice ALTER COLUMN notice_type DROP DEFAULT;
        ALTER TABLE sys_notice ALTER COLUMN notice_type TYPE varchar(32)
          USING CASE notice_type
            WHEN 1 THEN 'notification'
            WHEN 2 THEN 'announcement'
            ELSE notice_type::text
          END;
      ELSIF current_type = 'character varying' AND current_limit = 32 THEN
        -- 已完成的类型转换是安全重跑状态。
        NULL;
      ELSIF current_type IN ('character varying', 'text', 'character') THEN
        SELECT max(char_length(notice_type::text))
          INTO max_value_length
          FROM sys_notice;

        IF max_value_length > 32 THEN
          RAISE EXCEPTION 'sys_notice.notice_type contains values longer than 32 characters';
        END IF;

        ALTER TABLE sys_notice ALTER COLUMN notice_type DROP DEFAULT;
        ALTER TABLE sys_notice ALTER COLUMN notice_type TYPE varchar(32)
          USING notice_type::text;
      ELSE
        RAISE EXCEPTION 'unsupported sys_notice.notice_type type: %', current_type;
      END IF;

      IF EXISTS (SELECT 1 FROM sys_notice WHERE notice_type IS NULL) THEN
        UPDATE sys_notice SET notice_type = 'NOTICE' WHERE notice_type IS NULL;
      END IF;

      SELECT column_default, is_nullable
        INTO current_default, current_nullable
        FROM information_schema.columns
       WHERE table_schema = current_schema()
         AND table_name = 'sys_notice'
         AND column_name = 'notice_type';

      IF current_default IS DISTINCT FROM '''NOTICE''::character varying' THEN
        ALTER TABLE sys_notice ALTER COLUMN notice_type SET DEFAULT 'NOTICE';
      END IF;

      IF current_nullable = 'YES' THEN
        ALTER TABLE sys_notice ALTER COLUMN notice_type SET NOT NULL;
      END IF;
    END
    $notice_type_migration$;
    """)
  end

  def down do
    execute("""
    DO $notice_type_rollback$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM sys_notice
         WHERE notice_type NOT IN ('notification', 'announcement')
           AND notice_type !~ '^-?[0-9]+$'
      ) THEN
        RAISE EXCEPTION 'cannot restore integer notice types while custom values exist';
      END IF;

      ALTER TABLE sys_notice ALTER COLUMN notice_type DROP DEFAULT;
      ALTER TABLE sys_notice ALTER COLUMN notice_type TYPE smallint
        USING CASE notice_type
          WHEN 'notification' THEN 1
          WHEN 'announcement' THEN 2
          ELSE notice_type::smallint
        END;
    END
    $notice_type_rollback$;
    """)
  end
end
