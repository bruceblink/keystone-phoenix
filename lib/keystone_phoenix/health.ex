defmodule KeystonePhoenix.Health do
  @moduledoc "Runtime readiness checks for PostgreSQL and the local ETS store."

  alias KeystonePhoenix.Repo

  @doc "Returns dependency status without exposing connection details."
  def readiness do
    database = database_status()
    ready? = database == "UP"

    %{
      "status" => if(ready?, do: "READY", else: "NOT_READY"),
      "database" => database,
      "cache" => "ETS"
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
end
