defmodule KeystonePhoenix.Authz.Command do
  @moduledoc "Shared principal and actor extraction for domain write commands."

  alias KeystonePhoenix.Authz

  @doc "Checks a command permission carried by keyword authorization options."
  def authorize(options, permission) do
    with {:ok, principal} <- principal(options),
         :ok <- Authz.authorize(principal, permission) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "检查命令权限和已登记资源的数据范围。"
  def authorize_resource(options, permission, resource, context \\ %{})

  def authorize_resource(options, permission, resource, context)
      when is_list(options) and is_binary(permission) and is_map(context) do
    with {:ok, principal} <- principal(options),
         :ok <- Authz.authorize(principal, permission),
         true <- Authz.resource_scope_allowed?(principal, resource, context) do
      :ok
    else
      false -> {:error, :data_scope_denied}
      {:error, reason} -> {:error, reason}
    end
  end

  def authorize_resource(_options, _permission, _resource, _context),
    do: {:error, :authorization_required}

  @doc "Returns the principal carried by keyword authorization options."
  def principal(options) do
    case Keyword.get(options, :authorization) do
      authorization when is_map(authorization) ->
        principal = Map.get(authorization, :principal, Map.get(authorization, "principal"))
        if is_map(principal), do: {:ok, principal}, else: {:error, :authorization_required}

      _ ->
        {:error, :authorization_required}
    end
  end

  @doc "Returns an audit actor ID from options or the principal subject."
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
