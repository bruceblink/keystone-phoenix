defmodule KeystonePhoenix.IntegrityConstraintsTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Repo

  test "integrity foreign keys are installed for managed associations" do
    {:ok, result} =
      Repo.query("""
      SELECT conname
      FROM pg_constraint
      WHERE contype = 'f'
      ORDER BY conname
      """)

    constraint_names = result.rows |> Enum.map(&hd/1) |> MapSet.new()

    assert MapSet.subset?(
             MapSet.new([
               "auth_sessions_user_id_fkey",
               "sys_notice_owner_id_fkey",
               "sys_job_created_by_fkey",
               "sys_user_notification_user_id_fkey",
               "sys_user_role_user_id_fkey",
               "sys_user_role_role_id_fkey"
             ]),
             constraint_names
           )
  end
end
