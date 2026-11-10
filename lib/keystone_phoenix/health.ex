defmodule KeystonePhoenix.Health do
  @moduledoc "Runtime readiness checks for PostgreSQL and the local ETS store."

  alias KeystonePhoenix.Repo

  @doc "Returns dependency status without exposing connection details."
  def readiness do
    database = database_status()
    cache = cache_status()
    ready? = database == "UP" and cache == "UP"

    %{
      "status" => if(ready?, do: "READY", else: "NOT_READY"),
      "database" => database,
      "cache" => cache
    }
  end

  defp cache_status do
    tables = [
      KeystonePhoenix.RuntimeStore.cache_table(),
      KeystonePhoenix.RuntimeStore.captcha_table(),
      KeystonePhoenix.RuntimeStore.rate_limit_table()
    ]

    if Enum.all?(tables, &table_available?/1), do: "UP", else: "DOWN"
  rescue
    _error -> "DOWN"
  end

  defp table_available?(table) do
    case :ets.info(table, :size) do
      :undefined -> false
      _size -> true
    end
  end

  defp database_status do
    case Repo.query("SELECT 1") do
      {:ok, _result} -> "UP"
      _ -> "DOWN"
    end
  rescue
    _error -> "DOWN"
  end
end
