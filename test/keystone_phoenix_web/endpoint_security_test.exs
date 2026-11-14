defmodule KeystonePhoenixWeb.EndpointSecurityTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Endpoint

  test "browser session cookie uses explicit safe attributes" do
    options = Endpoint.session_options()

    assert options[:http_only] == true
    assert options[:same_site] == "Lax"
    assert options[:secure] == false
  end
end
