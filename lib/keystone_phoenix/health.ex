defmodule KeystonePhoenix.Health do
  @moduledoc "Runtime readiness checks for PostgreSQL and Redis."

  alias KeystonePhoenix.Repo

  @doc "Returns dependency status without exposing connection details."
  def readiness do
    database = database_status()
    redis = redis_status()
    ready? = database == "UP" and redis in ["UP", "DISABLED"]

    %{
      "status" => if(ready?, do: "READY", else: "NOT_READY"),
      "database" => database,
      "redis" => redis
    }
  end

  defp database_status do
    case Repo.query("SELECT 1") do
      {:ok, _result} -> "UP"
      _ -> "DOWN"
    end
  rescue
    _error -> "DOWN"
  end

  defp redis_status do
    if Application.get_env(:keystone_phoenix, :redis_enabled, true) do
      case Redix.command(KeystonePhoenix.Redis, ["PING"]) do
        {:ok, "PONG"} -> "UP"
        _ -> "DOWN"
      end
    else
      "DISABLED"
    end
  rescue
    _error -> "DOWN"
  catch
    :exit, _reason -> "DOWN"
  end
end
