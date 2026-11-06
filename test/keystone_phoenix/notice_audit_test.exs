defmodule KeystonePhoenix.NoticeAuditTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Notice
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  test "notice writes actor IDs and exposes the creator name" do
    actor =
      %SysUser{user_id: 701}
      |> SysUser.create_changeset(%{username: unique("notice_actor"), password: "Strong!123"})
      |> Repo.insert!()

    assert {:ok, notice} =
             Notice.create_notice(
               %{
                 "noticeTitle" => "审计通知",
                 "noticeType" => 1,
                 "noticeContent" => "内容",
                 "status" => 1
               },
               actor.user_id
             )

    assert notice.creator_id == actor.user_id

    assert {:ok, updated} =
             Notice.update_notice(notice.notice_id, %{"status" => 0}, actor.user_id)

    assert updated.updater_id == actor.user_id

    row =
      Notice.list_notices(%{"pageSize" => 10}).rows
      |> Enum.find(&(&1["noticeId"] == notice.notice_id))

    assert row["creatorName"] == actor.username
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
