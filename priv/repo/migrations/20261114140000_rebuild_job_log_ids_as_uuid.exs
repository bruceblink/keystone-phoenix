defmodule KeystonePhoenix.Repo.Migrations.RebuildJobLogIdsAsUuid do
  use Ecto.Migration

  @moduledoc """
  一次性重建任务和日志身份列。

  旧整数任务、任务日志和审计日志属于本次破坏性重构范围。迁移删除旧表，
  使用 PostgreSQL uuid 重建主键和直接关系；应用写入时生成 UUIDv7。
  """

  def up do
    unless uuid_ready?() do
      execute(
        "DROP TABLE IF EXISTS sys_job_log, sys_job, sys_login_info, sys_operation_log CASCADE"
      )

      create_tables()
    end
  end

  def down do
    # 整数身份不可逆转换。回滚边界是恢复应用版本和数据库备份。
    :ok
  end

  defp uuid_ready? do
    %{rows: [[count]]} =
      repo().query!("""
      SELECT COUNT(*)
      FROM information_schema.columns
      WHERE table_schema = current_schema()
        AND data_type = 'uuid'
        AND (
          (table_name = 'sys_job' AND column_name IN ('job_id', 'creator_id', 'updater_id'))
          OR (table_name = 'sys_job_log' AND column_name IN ('job_log_id', 'job_id'))
          OR (table_name = 'sys_login_info' AND column_name = 'info_id')
          OR (table_name = 'sys_operation_log' AND column_name IN ('operation_id', 'user_id', 'dept_id'))
        )
      """)

    count == 9
  end

  defp create_tables do
    execute("""
    CREATE TABLE sys_job (
      job_id uuid PRIMARY KEY,
      job_name varchar(64) NOT NULL DEFAULT '',
      job_group varchar(64) NOT NULL DEFAULT '',
      invoke_target varchar(255) NOT NULL DEFAULT '',
      job_params text,
      cron_expression varchar(255) NOT NULL DEFAULT '',
      concurrent smallint NOT NULL DEFAULT 0,
      status smallint NOT NULL DEFAULT 0,
      remark varchar(500),
      creator_id uuid,
      updater_id uuid,
      create_time timestamp(6) without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
      update_time timestamp(6) without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT sys_job_creator_id_fkey FOREIGN KEY (creator_id)
        REFERENCES sys_user(user_id) ON DELETE SET NULL,
      CONSTRAINT sys_job_updater_id_fkey FOREIGN KEY (updater_id)
        REFERENCES sys_user(user_id) ON DELETE SET NULL
    )
    """)

    execute("CREATE INDEX sys_job_group_index ON sys_job (job_group)")
    execute("CREATE INDEX sys_job_status_index ON sys_job (status)")

    execute("""
    CREATE TABLE sys_job_log (
      job_log_id uuid PRIMARY KEY,
      job_id uuid,
      job_name varchar(64) NOT NULL DEFAULT '',
      job_group varchar(64) NOT NULL DEFAULT '',
      invoke_target varchar(255) NOT NULL DEFAULT '',
      job_params text,
      cron_expression varchar(255),
      trigger_type smallint NOT NULL DEFAULT 1,
      status smallint NOT NULL DEFAULT 1,
      job_message varchar(500),
      exception_info varchar(2000),
      start_time timestamp(6) without time zone NOT NULL,
      end_time timestamp(6) without time zone,
      duration_ms bigint,
      create_time timestamp(6) without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT sys_job_log_job_id_fkey FOREIGN KEY (job_id)
        REFERENCES sys_job(job_id) ON DELETE SET NULL
    )
    """)

    execute("CREATE INDEX sys_job_log_job_id_index ON sys_job_log (job_id)")
    execute("CREATE INDEX sys_job_log_start_time_index ON sys_job_log (start_time)")
    execute("CREATE INDEX sys_job_log_status_index ON sys_job_log (status)")

    execute("""
    CREATE TABLE sys_login_info (
      info_id uuid PRIMARY KEY,
      username varchar(50) NOT NULL DEFAULT '',
      ip_address varchar(128) NOT NULL DEFAULT '',
      login_location varchar(255) NOT NULL DEFAULT '',
      browser varchar(50) NOT NULL DEFAULT '',
      operation_system varchar(50) NOT NULL DEFAULT '',
      status smallint NOT NULL DEFAULT 0,
      msg varchar(255) NOT NULL DEFAULT '',
      login_time timestamp(6) without time zone,
      deleted boolean NOT NULL DEFAULT false
    )
    """)

    execute("CREATE INDEX sys_login_info_username_index ON sys_login_info (username)")
    execute("CREATE INDEX sys_login_info_status_index ON sys_login_info (status)")

    execute("""
    CREATE TABLE sys_operation_log (
      operation_id uuid PRIMARY KEY,
      business_type smallint NOT NULL DEFAULT 0,
      request_method smallint NOT NULL DEFAULT 0,
      request_module varchar(64) NOT NULL DEFAULT '',
      request_url varchar(256) NOT NULL DEFAULT '',
      called_method varchar(128) NOT NULL DEFAULT '',
      operator_type smallint NOT NULL DEFAULT 1,
      user_id uuid,
      username varchar(32) NOT NULL DEFAULT '',
      operator_ip varchar(128) NOT NULL DEFAULT '',
      operator_location varchar(256),
      dept_id uuid,
      dept_name varchar(64),
      operation_param varchar(2048) NOT NULL DEFAULT '',
      operation_result varchar(2048) NOT NULL DEFAULT '',
      status smallint NOT NULL DEFAULT 1,
      error_stack varchar(2048) NOT NULL DEFAULT '',
      operation_time timestamp(6) without time zone NOT NULL,
      deleted boolean NOT NULL DEFAULT false,
      CONSTRAINT sys_operation_log_user_id_fkey FOREIGN KEY (user_id)
        REFERENCES sys_user(user_id) ON DELETE SET NULL,
      CONSTRAINT sys_operation_log_dept_id_fkey FOREIGN KEY (dept_id)
        REFERENCES sys_dept(dept_id) ON DELETE SET NULL
    )
    """)

    execute("CREATE INDEX sys_operation_log_user_id_index ON sys_operation_log (user_id)")

    execute(
      "CREATE INDEX sys_operation_log_operation_time_index ON sys_operation_log (operation_time)"
    )

    execute(
      "CREATE INDEX sys_login_info_deleted_time_index ON sys_login_info (deleted, login_time)"
    )

    execute(
      "CREATE INDEX sys_operation_log_deleted_time_index ON sys_operation_log (deleted, operation_time)"
    )
  end
end
