defmodule KeystonePhoenixWeb.HealthController do
  use KeystonePhoenixWeb, :controller

  alias KeystonePhoenixWeb.ApiResponse

  @doc """
  Returns the same lightweight liveness response as Keystone's Java service.
  """
  def show(conn, _params) do
    json(conn, ApiResponse.ok("is alive"))
  end
end
