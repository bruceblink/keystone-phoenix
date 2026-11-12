defmodule KeystonePhoenix.Authz.PolicyCache do
  @moduledoc "Versioned ETS-backed cache for role permission decisions."

  alias KeystonePhoenix.Cache
  alias KeystonePhoenix.Params

  @prefix "authz:policy:"
  @version_key {__MODULE__, :version}
  @default_ttl 30

  @doc "Caches a role permission decision while keeping storage errors uncached."
  def decision(role_id, permission, loader) when is_function(loader, 0) do
    with {:ok, role_id} <- Params.parse_positive_integer(role_id),
         true <- is_binary(permission) and permission != "" do
      key = key(role_id, permission)

      case Cache.fetch(key, ttl(), fn -> {:policy_cache_load, loader.()} end) do
        {:policy_cache_load, result} ->
          cache_result(key, result)

        result ->
          result
      end
    else
      _ -> loader.()
    end
  rescue
    _error -> loader.()
  end

  @doc "Invalidates all cached policy decisions and advances the policy version."
  def invalidate do
    next_version = version() + 1
    :persistent_term.put(@version_key, next_version)
    Cache.delete_prefix(@prefix)
    :ok
  rescue
    _error -> :ok
  end

  @doc "Returns the current node-local policy version."
  def version do
    :persistent_term.get(@version_key, 1)
  end

  defp cache_result(key, {:error, :authorization_unavailable} = error) do
    Cache.delete(key)
    error
  end

  defp cache_result(key, result) do
    Cache.put(key, result, ttl())
    result
  end

  defp key(role_id, permission), do: @prefix <> "v#{version()}:#{role_id}:#{permission}"

  defp ttl do
    Application.get_env(:keystone_phoenix, :authz_policy_cache_ttl, @default_ttl)
    |> max(1)
  end
end
