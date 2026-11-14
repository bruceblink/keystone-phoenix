defmodule KeystonePhoenix.Job.Authorization do
  @moduledoc "Principal authorization checks for scheduled job commands."

  alias KeystonePhoenix.Authz.Command

  # 任务命令必须同时通过操作权限和任务资源范围检查。
  def authorize(options, permission),
    do: Command.authorize_resource(options, permission, :job)

  # 任务查询入口复用同一授权上下文。
  def authorize_read(options, permission),
    do: Command.authorize_resource(options, permission, :job)

  # 自动调度器使用明确的内部主体，不继承外部用户权限。
  def system_options do
    [
      authorization: %{
        principal: %{data_scope: "ALL", permissions: ["job:read", "job:run"]},
        source: :scheduler
      }
    ]
  end
end
