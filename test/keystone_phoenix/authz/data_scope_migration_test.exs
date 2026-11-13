defmodule KeystonePhoenix.Authz.DataScopeMigrationTest do
  use ExUnit.Case, async: true

  test "role data scope migration stores canonical names" do
    sql = File.read!("priv/repo/migrations/20261114161000_rebuild_role_data_scope_enum.exs")
    assert sql =~ "WHEN 1 THEN 'ALL'"
    assert sql =~ "WHEN 4 THEN 'DEPARTMENT_AND_CHILDREN'"
    assert sql =~ "ALTER COLUMN data_scope TYPE varchar(32)"
  end
end
