defmodule KeystonePhoenix.ConfigDictionaryAuditTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  test "configuration and dictionary writes store the authenticated actor" do
    actor =
      %SysUser{user_id: 801}
      |> SysUser.create_changeset(%{username: unique("settings_actor"), password: "Strong!123"})
      |> Repo.insert!()

    assert {:ok, config} =
             Config.create_config(
               %{
                 "configName" => "审计配置",
                 "configKey" => unique("audit.config"),
                 "configValue" => "enabled",
                 "configOptions" => ["enabled", "disabled"],
                 "isAllowChange" => 1
               },
               actor.user_id
             )

    assert config.creator_id == actor.user_id

    assert {:ok, updated_config} =
             Config.update_config(config.config_id, %{"configValue" => "disabled"}, actor.user_id)

    assert updated_config.updater_id == actor.user_id

    assert {:ok, dict_type} =
             Dictionary.create_dict_type(
               %{"dictName" => "审计字典", "dictType" => unique("audit.dict"), "status" => 1},
               actor.user_id
             )

    assert dict_type.creator_id == actor.user_id

    assert {:ok, dict_data} =
             Dictionary.create_dict_data(
               %{
                 "dictType" => dict_type.dict_type,
                 "dictLabel" => "启用",
                 "dictValue" => 1,
                 "dictSort" => 1,
                 "isDefault" => 1,
                 "status" => 1
               },
               actor.user_id
             )

    assert dict_data.creator_id == actor.user_id

    assert {:ok, updated_data} =
             Dictionary.update_dict_data(
               dict_data.dict_code,
               %{"dictLabel" => "已启用"},
               actor.user_id
             )

    assert updated_data.updater_id == actor.user_id
  end

  test "immutable configuration and orphan dictionary data are rejected" do
    assert {:ok, config} =
             Config.create_config(%{
               "configName" => "不可修改配置",
               "configKey" => unique("immutable.config"),
               "configValue" => "enabled",
               "isAllowChange" => false
             })

    assert {:error, :not_allow_change} =
             Config.update_config(config.config_id, %{"configValue" => "disabled"})

    assert {:error, :dict_type_not_found} =
             Dictionary.create_dict_data(%{
               "dictType" => unique("missing.dict"),
               "dictLabel" => "孤立",
               "dictValue" => 1,
               "status" => 1
             })
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
