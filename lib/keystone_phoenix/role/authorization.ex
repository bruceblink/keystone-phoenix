defmodule KeystonePhoenix.Role.Authorization do
  @moduledoc "Principal authorization checks for role write commands."

  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Authz.Command

  # 角色查询和导出必须经过统一资源范围检查。
  def authorize_read(options, permission),
    do: Command.authorize_resource(options, permission, :role)

  def authorize_write(options, permission, attrs \\ %{}) do
    with {:ok, principal} <- principal(options),
         :ok <- Command.authorize_resource(options, permission, :role),
         true <- Authz.role_metadata_allowed?(principal, attrs) do
      :ok
    else
      false -> {:error, :permission_denied}
      {:error, reason} -> {:error, reason}
    end
  end

  def authorize_assignment(options, permission),
    do: authorize_assignment(options, permission, nil)

  @doc "Checks role resource scope before assignment commands run."
  def authorize_assignment(options, permission, user_ids) when is_list(options) do
    case Command.authorize_resource(options, permission, :role) do
      :ok ->
        with {:ok, principal} <- principal(options),
             true <- is_nil(user_ids) or assignment_targets_allowed?(principal, user_ids) do
          :ok
        else
          false -> {:error, :data_scope_denied}
          {:error, reason} -> {:error, reason}
        end

      {:error, :permission_denied} ->
        # Assignment endpoints historically use forbidden for a missing command permission.
        {:error, :forbidden}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def authorize_assignment(_options, _permission, _user_ids),
    do: {:error, :authorization_required}

  defp assignment_targets_allowed?(principal, user_ids) do
    case direct_scope(principal) do
      scope when scope in ["ALL", "TENANT"] -> true
      _scope -> Authz.scope_allowed?(principal, :users, user_ids)
    end
  end

  defp direct_scope(principal) when is_map(principal) do
    principal
    |> Map.get(:data_scope, Map.get(principal, "data_scope", Map.get(principal, "dataScope")))
    |> case do
      scope when is_binary(scope) -> String.upcase(String.trim(scope))
      _scope -> nil
    end
  end

  defp direct_scope(_principal), do: nil

  @doc "Returns the normalized principal carried by authorization options."
  def principal(options) do
    case Keyword.get(options, :authorization) do
      authorization when is_map(authorization) ->
        principal = Map.get(authorization, :principal, Map.get(authorization, "principal"))
        if is_map(principal), do: {:ok, principal}, else: {:error, :authorization_required}

      _ ->
        {:error, :authorization_required}
    end
  end

  def actor_id(options) do
    authorization = Keyword.fetch!(options, :authorization)
    actor_id = Map.get(authorization, :actor_id, Map.get(authorization, "actor_id"))

    actor_id ||
      authorization
      |> Map.get(:principal, Map.get(authorization, "principal"))
      |> Authz.Principal.from_user()
      |> Map.get(:subject_id)
  end
end
