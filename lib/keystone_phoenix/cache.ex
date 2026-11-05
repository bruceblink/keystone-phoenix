defmodule KeystonePhoenix.Cache do
  @moduledoc """
  Small Redis cache boundary with a database fallback.

  Cache failures are deliberately ignored so Redis availability does not make
  dictionary reads unavailable.
  """

  @redis_name KeystonePhoenix.Redis
  @delete_batch_size 500

  @spec fetch(String.t(), pos_integer(), (-> term())) :: term()
  def fetch(key, ttl_seconds, loader) when is_function(loader, 0) do
    case get(key) do
      {:ok, value} ->
        value

      :miss ->
        value = loader.()
        put(key, value, ttl_seconds)
        value
    end
  end

  @spec put(String.t(), term(), pos_integer()) :: :ok
  def put(key, value, ttl_seconds) do
    with {:ok, encoded} <- Jason.encode(value),
         {:ok, "OK"} <-
           Redix.command(@redis_name, ["SET", key, encoded, "EX", Integer.to_string(ttl_seconds)]) do
      :ok
    else
      _ -> :ok
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  @spec delete(String.t()) :: :ok
  def delete(key) do
    Redix.command(@redis_name, ["DEL", key])
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  @spec delete_prefix(String.t()) :: :ok
  def delete_prefix(prefix) do
    prefix
    |> scan_keys()
    |> delete_many()

    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp get(key) do
    case Redix.command(@redis_name, ["GET", key]) do
      {:ok, nil} -> :miss
      {:ok, encoded} -> decode(encoded)
      _ -> :miss
    end
  rescue
    _ -> :miss
  catch
    :exit, _ -> :miss
  end

  defp decode(encoded) do
    case Jason.decode(encoded) do
      {:ok, value} -> {:ok, value}
      _ -> :miss
    end
  end

  defp delete_many([]), do: :ok

  defp delete_many(keys) do
    keys
    |> Enum.chunk_every(@delete_batch_size)
    |> Enum.each(fn chunk -> Redix.command(@redis_name, ["DEL" | chunk]) end)

    :ok
  end

  defp scan_keys(prefix), do: scan_keys("0", "#{prefix}*", [])

  defp scan_keys(cursor, pattern, keys) do
    case Redix.command(@redis_name, ["SCAN", cursor, "MATCH", pattern, "COUNT", "100"]) do
      {:ok, [next_cursor, found_keys]} when is_binary(next_cursor) and is_list(found_keys) ->
        keys = [found_keys | keys]

        if next_cursor == "0" do
          List.flatten(Enum.reverse(keys))
        else
          scan_keys(next_cursor, pattern, keys)
        end

      _ ->
        keys
    end
  end
end
