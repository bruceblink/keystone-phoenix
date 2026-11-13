defmodule KeystonePhoenix.Authz.DataScopeTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Authz.DataScope

  test "exposes the shared scope directory and resource matrix" do
    assert DataScope.registered?("tenant")
    assert DataScope.supported?(:user, "TENANT")
    assert DataScope.supported?(:owned, "MEMBER")
    refute DataScope.supported?(:user, "OWNER")
    refute DataScope.registered?("UNKNOWN")
  end
end
