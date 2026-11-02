defmodule KeystonePhoenix.Auth.Session do
  @moduledoc "Redis-backed refresh token sessions."

  @redis_name KeystonePhoenix.Redis
  @key_prefix "keystone:auth:refresh:"

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

  @spec delete(String.t()) :: :ok
  def delete(jti) do
    command(["DEL", key(jti)])
    :ok
  end

  defp key(jti), do: @key_prefix <> jti

  defp command(command) do
    Redix.command(@redis_name, command)
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
