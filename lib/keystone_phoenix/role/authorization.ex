defmodule KeystonePhoenix.Role.Authorization do
  @moduledoc "Principal authorization checks for role write commands."

  alias KeystonePhoenix.Authz

  def authorize_write(options, permission, attrs \\ %{}) do
    with {:ok, principal} <- principal(options),
         true <- Authz.allowed?(principal, permission),
         true <- Authz.role_metadata_allowed?(principal, attrs) do
      :ok
    else
      false -> {:error, :permission_denied}
      {:error, reason} -> {:error, reason}
    end
  end

  def authorize_assignment(options, permission) do
    with {:ok, principal} <- principal(options),
         true <- Authz.allowed?(principal, permission),
         true <- Authz.admin?(principal) do
      :ok
    else
      false -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

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
