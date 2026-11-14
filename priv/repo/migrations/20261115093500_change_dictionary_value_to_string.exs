defmodule KeystonePhoenix.Repo.Migrations.ChangeDictionaryValueToString do
  use Ecto.Migration

  @moduledoc "将字典值保存为字符串，使其符合 Native 字典条目 DTO。"

  def up do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'sys_dict_data'
          AND column_name = 'dict_value'
          AND data_type <> 'character varying'
      ) THEN
        ALTER TABLE sys_dict_data
          ALTER COLUMN dict_value TYPE varchar(128) USING dict_value::text;
      END IF;
    END $$;
    """)

    execute("ALTER TABLE sys_dict_data ALTER COLUMN dict_value SET DEFAULT ''")
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'sys_dict_data'
          AND column_name = 'dict_value'
          AND data_type = 'character varying'
      ) AND NOT EXISTS (
        SELECT 1 FROM sys_dict_data WHERE dict_value !~ '^-?[0-9]+$'
      ) THEN
        ALTER TABLE sys_dict_data
          ALTER COLUMN dict_value TYPE integer USING dict_value::integer;
        ALTER TABLE sys_dict_data ALTER COLUMN dict_value SET DEFAULT 0;
      END IF;
    END $$;
    """)
  end
end
