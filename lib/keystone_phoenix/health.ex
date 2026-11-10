defmodule KeystonePhoenix.Health do
  @moduledoc "Runtime readiness checks for PostgreSQL, ETS, and file storage."

  alias KeystonePhoenix.Repo

  @doc "Returns dependency status without exposing connection details."
  def readiness do
    database = database_status()
    cache = cache_status()
    storage = storage_status()
    ready? = database == "UP" and cache == "UP" and storage == "UP"

    %{
      "status" => if(ready?, do: "READY", else: "NOT_READY"),
      "database" => database,
      "cache" => cache,
      "storage" => storage
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

  defp storage_status do
    directory = Application.get_env(:keystone_phoenix, :file_base_dir, "uploads")
    probe = Path.join(Path.expand(directory), ".keystone-write-probe-#{System.unique_integer()}")

    with :ok <- File.mkdir_p(Path.dirname(probe)),
         :ok <- File.write(probe, "ok", [:exclusive]),
         :ok <- File.rm(probe) do
      "UP"
    else
      _ ->
        _ = File.rm(probe)
        "DOWN"
    end
  rescue
    _error -> "DOWN"
  end
end
