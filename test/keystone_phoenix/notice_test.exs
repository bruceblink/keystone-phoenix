defmodule KeystonePhoenix.NoticeTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Notice
  alias KeystonePhoenix.Notice.SysNotice

  test "maps notice fields without exposing persistence flags" do
    notice = %SysNotice{
      notice_id: 7,
      notice_title: "维护通知",
      notice_type: 1,
      notice_content: "服务将在周末维护。",
      status: 1,
      creator_id: 7,
      remark: "管理员",
      deleted: false,
      create_time: ~U[2026-11-04 04:00:00Z]
    }

    assert Notice.notice_to_map(notice) == %{
             "noticeId" => 7,
             "noticeTitle" => "维护通知",
             "noticeType" => 1,
             "noticeContent" => "服务将在周末维护。",
             "status" => 1,
             "creatorName" => "",
             "remark" => "管理员",
             "createTime" => "2026-11-04 04:00:00"
           }

    assert Notice.notice_to_map(notice, %{7 => "admin"})["creatorName"] == "admin"
  end

  test "rejects non-map create and update inputs at the domain boundary" do
    assert {:error, :authorization_required} = Notice.create_notice(:invalid, [])
    assert {:error, :authorization_required} = Notice.update_notice(1, :invalid, [])
  end

  test "rejects invalid deletion IDs before accessing the database" do
    authorization = [authorization: %{principal: %{}}]
    assert {:error, :invalid_ids} = Notice.delete_notices([], authorization)
    assert {:error, :invalid_ids} = Notice.delete_notices(["bad-id"], authorization)
  end
end
