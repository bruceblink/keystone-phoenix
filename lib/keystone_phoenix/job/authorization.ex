defmodule KeystonePhoenix.Job.Authorization do
  @moduledoc "Principal authorization checks for scheduled job commands."

  alias KeystonePhoenix.Authz.Command

  def authorize(options, permission), do: Command.authorize(options, permission)
end
