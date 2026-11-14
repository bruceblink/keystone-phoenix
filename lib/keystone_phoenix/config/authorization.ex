defmodule KeystonePhoenix.Config.Authorization do
  @moduledoc "Principal authorization checks for configuration commands."

  alias KeystonePhoenix.Authz.Command
  alias KeystonePhoenix.Authz.Principal

  # 配置命令统一检查操作权限和配置资源范围。
  def authorize(options, permission),
    do: Command.authorize_resource(options, permission, :config)

  # 配置查询入口使用与写入相同的授权上下文。
  def authorize_read(options, permission),
    do: Command.authorize_resource(options, permission, :config)

  def actor_id(options) do
    authorization = Keyword.fetch!(options, :authorization)
    actor_id = Map.get(authorization, :actor_id, Map.get(authorization, "actor_id"))

    actor_id ||
      authorization
      |> Map.get(:principal, Map.get(authorization, "principal"))
      |> Principal.from_user()
      |> Map.get(:subject_id)
  end
end
