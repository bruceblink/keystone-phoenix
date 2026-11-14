defmodule KeystonePhoenix.Post.Authorization do
  @moduledoc "Principal authorization checks for post commands."

  alias KeystonePhoenix.Authz.Command

  # 岗位命令必须同时通过操作权限和岗位资源的数据范围检查。
  def authorize(options, permission), do: Command.authorize_resource(options, permission, :post)

  # 查询入口复用同一授权上下文，避免服务层调用绕过资源范围规则。
  def authorize_read(options, permission),
    do: Command.authorize_resource(options, permission, :post)
end
