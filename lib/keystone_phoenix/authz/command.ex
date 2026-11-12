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
