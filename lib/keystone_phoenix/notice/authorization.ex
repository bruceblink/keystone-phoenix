defmodule KeystonePhoenix.Notice.Authorization do
  @moduledoc "Principal authorization checks for notice commands."

  alias KeystonePhoenix.Authz.Command

  # 公告命令返回全量或当前主体拥有者范围，供查询和写入同时使用。
  def authorize_owner(options, permission),
    do: Command.authorize_owner(options, permission, :notice)
end
