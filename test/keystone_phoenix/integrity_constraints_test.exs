defmodule KeystonePhoenix.IntegrityConstraintsTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Repo

  test "integrity foreign keys are installed for managed associations" do
    {:ok, result} =
      Repo.query("""
      SELECT COUNT(*)
      FROM pg_constraint
      WHERE contype = 'f'
      """)

    assert result.rows == [[44]]
  end
end
