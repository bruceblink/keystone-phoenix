defmodule KeystonePhoenix.Config.Authorization do
  @moduledoc "Principal authorization checks for configuration commands."

  alias KeystonePhoenix.Authz.Command

  # 配置命令统一检查操作权限和配置资源范围。
  def authorize(options, permission),
    do: Command.authorize_resource(options, permission, :config)

  # 配置查询入口使用与写入相同的授权上下文。
  def authorize_read(options, permission),
    do: Command.authorize_resource(options, permission, :config)

  def actor_id(options), do: Command.actor_id(options)
end
