defmodule KeystonePhoenix.Repo.Migrations.RebuildNoticeConfigDictionaryIdsAsUuid do
  use Ecto.Migration

  alias KeystonePhoenix.Identity

  @moduledoc """
  一次性重建公告、配置和字典身份列。

  旧整数记录属于可破坏的系统初始化数据。迁移清空四张表，改用 PostgreSQL
  uuid 主键和用户 UUID 审计字段，再写入固定 UUIDv5 启动记录。
  """

  @tables ~w(sys_notice sys_config sys_dict_data sys_dict_type)

  def up do
    unless uuid_ready?() do
      drop_foreign_keys()
      execute("TRUNCATE TABLE sys_dict_data, sys_dict_type, sys_config, sys_notice CASCADE")
      alter_identity_columns()
      create_foreign_keys()
    end

    ensure_bootstrap_records()
  end

  def down do
    # 整数身份不能安全反向转换。回滚边界是恢复应用版本和数据库备份。
    :ok
  end

  defp uuid_ready? do
    %{rows: [[count]]} =
      repo().query!("""
      SELECT COUNT(*)
      FROM information_schema.columns
      WHERE table_schema = current_schema()
        AND data_type = 'uuid'
        AND ((table_name = 'sys_notice' AND column_name IN ('notice_id', 'creator_id', 'updater_id'))
          OR (table_name = 'sys_config' AND column_name IN ('config_id', 'creator_id', 'updater_id'))
          OR (table_name = 'sys_dict_type' AND column_name IN ('dict_id', 'creator_id', 'updater_id'))
          OR (table_name = 'sys_dict_data' AND column_name IN ('dict_code', 'creator_id', 'updater_id')))
      """)

    count == 12
  end

  defp drop_foreign_keys do
    execute("""
    DO $$
    DECLARE item record;
    BEGIN
      FOR item IN
        SELECT conrelid::regclass AS table_name, conname AS constraint_name
        FROM pg_constraint
        WHERE contype = 'f'
          AND (conrelid IN ('sys_notice'::regclass, 'sys_config'::regclass,
                            'sys_dict_type'::regclass, 'sys_dict_data'::regclass)
               OR confrelid IN ('sys_notice'::regclass, 'sys_config'::regclass,
                                'sys_dict_type'::regclass, 'sys_dict_data'::regclass))
      LOOP
        EXECUTE format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I',
                       item.table_name, item.constraint_name);
      END LOOP;
    END $$;
    """)
  end

  defp alter_identity_columns do
    for {table, columns} <- [
          {"sys_notice", ~w(notice_id creator_id updater_id)},
          {"sys_config", ~w(config_id creator_id updater_id)},
          {"sys_dict_type", ~w(dict_id creator_id updater_id)},
          {"sys_dict_data", ~w(dict_code creator_id updater_id)}
        ] do
      for column <- columns do
        execute("ALTER TABLE #{table} ALTER COLUMN #{column} DROP DEFAULT")
        execute("ALTER TABLE #{table} ALTER COLUMN #{column} TYPE uuid USING NULL::uuid")
      end
    end
  end

  defp create_foreign_keys do
    for table <- @tables do
      for column <- ~w(creator_id updater_id) do
        execute("""
        ALTER TABLE #{table}
        ADD CONSTRAINT #{table}_#{column}_fk
        FOREIGN KEY (#{column}) REFERENCES sys_user (user_id) ON DELETE SET NULL
        """)
      end
    end

    execute("""
    ALTER TABLE sys_dict_data
    ADD CONSTRAINT sys_dict_data_dict_type_fk
    FOREIGN KEY (dict_type) REFERENCES sys_dict_type (dict_type) ON DELETE RESTRICT
    """)
  end

  defp ensure_bootstrap_records do
    namespace = Identity.permission_namespace()
    notice_id = Identity.v5(namespace, "system:notice:maintenance")
    config_id = Identity.v5(namespace, "system:config:captcha")
    yes_type_id = Identity.v5(namespace, "system:dictionary:common.yesOrNo")
    status_type_id = Identity.v5(namespace, "system:dictionary:common.status")
    yes_id = Identity.v5(namespace, "system:dictionary:common.yesOrNo:yes")
    no_id = Identity.v5(namespace, "system:dictionary:common.yesOrNo:no")
    enabled_id = Identity.v5(namespace, "system:dictionary:common.status:enabled")
    disabled_id = Identity.v5(namespace, "system:dictionary:common.status:disabled")

    execute("""
    INSERT INTO sys_notice
      (notice_id, notice_title, notice_type, notice_content, status, remark, deleted, create_time, update_time)
    VALUES ('#{notice_id}'::uuid, '系统维护通知', 1, '请在维护窗口前保存工作。', 1, '系统初始化公告', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    ON CONFLICT (notice_id) DO NOTHING
    """)

    execute("""
    INSERT INTO sys_config
      (config_id, config_name, config_key, config_options, config_value, is_allow_change, remark, deleted, create_time, update_time)
    VALUES ('#{config_id}'::uuid, '账号自助-验证码开关', 'sys.account.captchaOnOff', '["true","false"]', 'false', false, '系统初始化配置', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    ON CONFLICT (config_id) DO NOTHING
    """)

    execute("""
    INSERT INTO sys_dict_type
      (dict_id, dict_name, dict_type, status, remark, deleted, create_time, update_time)
    VALUES
      ('#{yes_type_id}'::uuid, '系统是否', 'common.yesOrNo', 1, '系统是否列表', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('#{status_type_id}'::uuid, '通用状态', 'common.status', 1, '通用状态列表', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    ON CONFLICT (dict_id) DO NOTHING
    """)

    execute("""
    INSERT INTO sys_dict_data
      (dict_code, dict_type, dict_label, dict_value, dict_sort, is_default, list_class, status, remark, deleted, create_time, update_time)
    VALUES
      ('#{yes_id}'::uuid, 'common.yesOrNo', '是', 1, 1, false, '', 1, '是', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('#{no_id}'::uuid, 'common.yesOrNo', '否', 0, 2, false, 'danger', 1, '否', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('#{enabled_id}'::uuid, 'common.status', '正常', 1, 1, false, '', 1, '正常状态', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('#{disabled_id}'::uuid, 'common.status', '停用', 0, 2, false, 'danger', 1, '停用状态', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    ON CONFLICT (dict_code) DO NOTHING
    """)
  end
end
