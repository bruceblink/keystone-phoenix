defmodule KeystonePhoenix.Department.Authorization do
  @moduledoc "Principal authorization checks for department commands."

  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Authz.Command

  def authorize_create(options), do: Command.authorize(options, "system:dept:add")

  def authorize_target(options, permission, id) do
    with :ok <- Command.authorize(options, permission),
         {:ok, principal} <- Command.principal(options),
         true <- Authz.scope_allowed?(principal, :dept, id) do
      :ok
    else
      false -> {:error, :data_scope_denied}
      {:error, reason} -> {:error, reason}
    end
  end
end
