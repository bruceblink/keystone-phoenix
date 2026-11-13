defmodule KeystonePhoenix.Authz.PermissionCatalogTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Authz.PermissionCatalog

  test "exposes metadata for registered permissions" do
    entry = Enum.find(PermissionCatalog.entries(), &(&1.permission == "user:delete"))

    assert entry.resource == "user"
    assert entry.domain == "default"
    assert entry.action == "delete"
    assert entry.risk == :high
    refute entry.deprecated
    assert entry.registered?
  end

  test "normalizes and validates known and future permission strings" do
    assert {:ok, %{permission: "user:update", registered?: true}} =
             PermissionCatalog.validate(" user:update ")

    assert {:ok, %{permission: "report:read", registered?: false}} =
             PermissionCatalog.validate("report:read")

    assert {:error, :empty_permission} = PermissionCatalog.validate(" ")
    assert {:error, :invalid_permission} = PermissionCatalog.validate("system:user:edit")
  end

  test "rejects duplicate and malformed catalog entries" do
    assert {:error, %{duplicates: ["user:read"], invalid: ["bad"]}} =
             PermissionCatalog.validate_catalog(["user:read", "user:read", "bad"])
  end
end
