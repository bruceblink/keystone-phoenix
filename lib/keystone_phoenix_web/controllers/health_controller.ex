defmodule KeystonePhoenixWeb.HealthController do
  use KeystonePhoenixWeb, :controller

  alias KeystonePhoenix.Health
  alias KeystonePhoenixWeb.ApiResponse

  @doc """
  Returns the same lightweight liveness response as Keystone's Java service.
  """
  def show(conn, _params) do
    json(conn, ApiResponse.ok("is alive"))
  end

  @doc "Returns dependency readiness for container and load-balancer probes."
  def readiness(conn, _params) do
    readiness = Health.readiness()
    status = if readiness["status"] == "READY", do: :ok, else: :service_unavailable

    conn
    |> put_status(status)
    |> json(ApiResponse.ok(readiness))
  end
end
