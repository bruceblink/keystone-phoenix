defmodule KeystonePhoenix.Authz.PermissionCatalogTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Authz.PermissionCatalog

  test "exposes metadata for registered permissions" do
    entry = Enum.find(PermissionCatalog.entries(), &(&1.permission == "system:user:remove"))

    assert entry.resource == "system"
    assert entry.domain == "user"
    assert entry.action == "remove"
    assert entry.risk == :high
    refute entry.deprecated
    assert entry.registered?
  end

  test "normalizes and validates known and future permission strings" do
    assert {:ok, %{permission: "system:user:edit", registered?: true}} =
             PermissionCatalog.validate(" system:user:edit ")

    assert {:ok, %{permission: "system:report:read", registered?: false}} =
             PermissionCatalog.validate("system:report:read")

    assert {:error, :empty_permission} = PermissionCatalog.validate(" ")
    assert {:error, :invalid_permission} = PermissionCatalog.validate("system:user")
  end

  test "rejects duplicate and malformed catalog entries" do
    assert {:error, %{duplicates: ["system:user:list"], invalid: ["bad"]}} =
             PermissionCatalog.validate_catalog(["system:user:list", "system:user:list", "bad"])
  end
end
