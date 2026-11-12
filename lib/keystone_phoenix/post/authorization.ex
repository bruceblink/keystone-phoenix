defmodule KeystonePhoenix.Post.Authorization do
  @moduledoc "Principal authorization checks for post commands."

  alias KeystonePhoenix.Authz.Command

  def authorize(options, permission), do: Command.authorize(options, permission)
end
