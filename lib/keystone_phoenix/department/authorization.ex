defmodule KeystonePhoenix.Department.Authorization do
  @moduledoc "Principal authorization checks for department commands."

  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Authz.Command

  def authorize_create(options, attrs \\ %{}) do
    with :ok <- Command.authorize(options, "department:create"),
         {:ok, principal} <- Command.principal(options),
         true <- Authz.scope_allowed?(principal, :dept_create, parent_id(attrs)) do
      :ok
    else
      false -> {:error, :data_scope_denied}
      {:error, reason} -> {:error, reason}
    end
  end

  def authorize_target(options, permission, id, attrs \\ %{}) do
    with :ok <- Command.authorize(options, permission),
         {:ok, principal} <- Command.principal(options),
         true <- Authz.scope_allowed?(principal, :dept_update, {id, parent_id(attrs)}) do
      :ok
    else
      false -> {:error, :data_scope_denied}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parent_id(attrs) when is_map(attrs),
    do: Map.get(attrs, "parentId", Map.get(attrs, :parent_id))

  defp parent_id(_attrs), do: nil
end
