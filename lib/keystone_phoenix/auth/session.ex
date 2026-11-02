defmodule KeystonePhoenix.Auth.Session do
  @moduledoc "Redis-backed refresh token sessions."

  @redis_name KeystonePhoenix.Redis
  @key_prefix "keystone:auth:refresh:"
  @account_prefix "keystone:auth:account:"

  @spec put(String.t(), integer(), pos_integer()) :: :ok | {:error, :unavailable}
  def put(jti, user_id, ttl) do
    case command(["SET", key(jti), to_string(user_id), "EX", Integer.to_string(ttl)]) do
      {:ok, "OK"} -> :ok
      _ -> {:error, :unavailable}
    end
  end

  @spec valid?(String.t(), integer()) :: boolean()
  def valid?(jti, user_id) do
    command(["GET", key(jti)]) == {:ok, to_string(user_id)}
  end

  @spec active?(integer(), String.t()) :: boolean()
  def active?(user_id, jti) do
    command(["GET", account_key(user_id)]) == {:ok, jti}
  end

  @spec occupy(integer(), String.t(), pos_integer(), boolean()) :: :ok | {:error, atom()}
  def occupy(user_id, jti, ttl, force_login \\ false) do
    account_key = account_key(user_id)

    case command(["GET", account_key]) do
      {:ok, nil} ->
        claim_account(account_key, jti, ttl)

      {:ok, ^jti} ->
        :ok

      {:ok, current_jti} when force_login ->
        delete(current_jti)
        command(["DEL", account_key])
        claim_account(account_key, jti, ttl)

      {:ok, _current_jti} ->
        {:error, :already_logged_in}

      {:error, :unavailable} ->
        {:error, :unavailable}

      _ ->
        {:error, :unavailable}
    end
  end

  @spec release(integer(), String.t()) :: :ok
  def release(user_id, jti) do
    account_key = account_key(user_id)

    if command(["GET", account_key]) == {:ok, jti} do
      command(["DEL", account_key])
    end

    :ok
  end

  @spec revoke(integer(), String.t()) :: :ok
  def revoke(user_id, jti) do
    delete(jti)
    release(user_id, jti)
  end

  @doc "Revokes the refresh session currently associated with a user account."
  @spec revoke_account(integer()) :: :ok
  def revoke_account(user_id) do
    case command(["GET", account_key(user_id)]) do
      {:ok, jti} when is_binary(jti) -> revoke(user_id, jti)
      _ -> :ok
    end
  end

  @spec delete(String.t()) :: :ok
  def delete(jti) do
    command(["DEL", key(jti)])
    :ok
  end

  defp key(jti), do: @key_prefix <> jti
  defp account_key(user_id), do: @account_prefix <> to_string(user_id)

  defp claim_account(account_key, jti, ttl) do
    case command(["SET", account_key, jti, "EX", Integer.to_string(ttl), "NX"]) do
      {:ok, "OK"} -> :ok
      {:ok, nil} -> {:error, :already_logged_in}
      {:error, :unavailable} -> {:error, :unavailable}
      _ -> {:error, :unavailable}
    end
  end

  defp command(command) do
    Redix.command(@redis_name, command)
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
