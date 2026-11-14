defmodule KeystonePhoenix.NoticeConfigDictionaryUuidTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Config.SysConfig
  alias KeystonePhoenix.Dictionary.{DictData, DictType}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Notice.SysNotice
  alias KeystonePhoenix.Repo

  test "notice, config and dictionary changesets generate UUIDv7 identifiers" do
    notice =
      SysNotice.changeset(%SysNotice{}, %{
        notice_title: "UUID 公告",
        notice_type: 1,
        notice_content: "内容"
      })

    config =
      SysConfig.changeset(%SysConfig{}, %{
        config_name: "UUID 配置",
        config_key: "uuid.config",
        config_value: "enabled"
      })

    dict_type = DictType.changeset(%DictType{}, %{dict_name: "UUID 字典", dict_type: "uuid.type"})

    dict_data =
      DictData.changeset(%DictData{}, %{
        dict_type: "uuid.type",
        dict_label: "启用",
        dict_value: 1
      })

    for {changeset, field} <- [
          {notice, :notice_id},
          {config, :config_id},
          {dict_type, :dict_id},
          {dict_data, :dict_code}
        ] do
      assert Identity.canonical?(Ecto.Changeset.get_change(changeset, field))
    end
  end

  test "migration uses UUID columns for the four system domains" do
    %{rows: rows} =
      Repo.query!("""
      SELECT table_name, column_name, data_type
      FROM information_schema.columns
      WHERE table_schema = current_schema()
        AND ((table_name = 'sys_notice' AND column_name IN ('notice_id', 'creator_id', 'owner_id', 'updater_id'))
          OR (table_name = 'sys_config' AND column_name IN ('config_id', 'creator_id', 'updater_id'))
          OR (table_name = 'sys_dict_type' AND column_name IN ('dict_id', 'creator_id', 'updater_id'))
          OR (table_name = 'sys_dict_data' AND column_name IN ('dict_code', 'creator_id', 'updater_id')))
      """)

    assert length(rows) == 13
    assert Enum.all?(rows, &(Enum.at(&1, 2) == "uuid"))
  end

  test "migration is guarded and seeds fixed records" do
    source =
      Path.expand(
        "../../priv/repo/migrations/20261114130000_rebuild_notice_config_dictionary_ids_as_uuid.exs",
        __DIR__
      )

    source = File.read!(source)
    assert source =~ "unless uuid_ready?()"
    assert source =~ "TRUNCATE TABLE sys_dict_data, sys_dict_type, sys_config, sys_notice CASCADE"
    assert source =~ "Identity.v5"
  end
end
