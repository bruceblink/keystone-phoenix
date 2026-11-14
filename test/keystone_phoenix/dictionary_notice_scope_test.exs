defmodule KeystonePhoenix.DictionaryNoticeScopeTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Notice

  test "dictionary service commands reject a department-scoped principal" do
    permissions = dictionary_permissions()
    authorization = [authorization: %{principal: principal("DEPARTMENT", permissions)}]

    assert {:error, :data_scope_denied} = Dictionary.list_dict_types(%{}, authorization)
    assert {:error, :data_scope_denied} = Dictionary.list_dict_data(%{}, authorization)

    assert {:error, :data_scope_denied} =
             Dictionary.list_dict_data_by_type("common.status", authorization)

    assert {:error, :data_scope_denied} = Dictionary.get_dict_type(Identity.v7(), authorization)
    assert {:error, :data_scope_denied} = Dictionary.get_dict_data(Identity.v7(), authorization)
    assert {:error, :data_scope_denied} = Dictionary.refresh_cache(authorization)

    assert {:error, :data_scope_denied} =
             Dictionary.create_dict_type(
               %{"dictName" => "越界字典", "dictType" => "scope.blocked"},
               authorization
             )

    assert {:error, :data_scope_denied} =
             Dictionary.update_dict_type(Identity.v7(), %{"dictName" => "越界修改"}, authorization)

    assert {:error, :data_scope_denied} =
             Dictionary.delete_dict_type(Identity.v7(), authorization)

    assert {:error, :data_scope_denied} = Dictionary.create_dict_data(%{}, authorization)

    assert {:error, :data_scope_denied} =
             Dictionary.update_dict_data(Identity.v7(), %{}, authorization)

    assert {:error, :data_scope_denied} =
             Dictionary.delete_dict_data(Identity.v7(), authorization)
  end

  test "dictionary tenant scope supports type and data lifecycle" do
    authorization = [authorization: %{principal: principal("TENANT", dictionary_permissions())}]
    dict_type = "scope.dict.#{System.unique_integer([:positive])}"

    assert {:ok, type} =
             Dictionary.create_dict_type(
               %{"dictName" => "范围字典", "dictType" => dict_type, "status" => 1},
               authorization
             )

    assert {:ok, types} = Dictionary.list_dict_types(%{"dictType" => dict_type}, authorization)
    assert Enum.any?(types.rows, &(&1["dictId"] == type.dict_id))
    assert {:ok, loaded_type} = Dictionary.get_dict_type(type.dict_id, authorization)
    assert loaded_type.dict_id == type.dict_id

    assert {:ok, data} =
             Dictionary.create_dict_data(
               %{
                 "dictType" => dict_type,
                 "dictLabel" => "启用",
                 "dictValue" => "1",
                 "dictSort" => 1,
                 "isDefault" => 1,
                 "status" => 1
               },
               authorization
             )

    assert {:ok, data_page} = Dictionary.list_dict_data(%{"dictType" => dict_type}, authorization)
    assert Enum.any?(data_page.rows, &(&1["dictCode"] == data.dict_code))
    assert {:ok, loaded_data} = Dictionary.get_dict_data(data.dict_code, authorization)
    assert loaded_data.dict_code == data.dict_code
    assert {:ok, by_type} = Dictionary.list_dict_data_by_type(dict_type, authorization)
    assert Enum.any?(by_type, &(&1["dictCode"] == data.dict_code))

    assert {:ok, updated_data} =
             Dictionary.update_dict_data(data.dict_code, %{"dictLabel" => "已启用"}, authorization)

    assert updated_data.dict_label == "已启用"
    assert :ok = Dictionary.delete_dict_data(data.dict_code, authorization)
    assert :ok = Dictionary.delete_dict_type(type.dict_id, authorization)
    assert :ok = Dictionary.refresh_cache(authorization)
  end

  test "notice service commands enforce scope for list, detail and lifecycle" do
    permissions = ["notice:read", "notice:create", "notice:update", "notice:delete"]
    blocked = [authorization: %{principal: principal("DEPARTMENT", permissions)}]

    assert {:error, :data_scope_denied} = Notice.list_notices(%{}, blocked)
    assert {:error, :data_scope_denied} = Notice.get_notice(Identity.v7(), blocked)

    assert {:error, :data_scope_denied} =
             Notice.create_notice(%{"noticeTitle" => "越界公告"}, blocked)

    assert {:error, :data_scope_denied} =
             Notice.update_notice(Identity.v7(), %{"status" => 0}, blocked)

    assert {:error, :data_scope_denied} = Notice.delete_notices([Identity.v7()], blocked)

    allowed = [authorization: %{principal: principal("TENANT", permissions)}]

    assert {:ok, notice} =
             Notice.create_notice(
               %{
                 "noticeTitle" => "范围公告",
                 "noticeType" => 1,
                 "noticeContent" => "内容",
                 "status" => 1
               },
               allowed
             )

    assert {:ok, page} = Notice.list_notices(%{"noticeTitle" => "范围公告"}, allowed)
    assert Enum.any?(page.rows, &(&1["noticeId"] == notice.notice_id))
    assert {:ok, loaded} = Notice.get_notice(notice.notice_id, allowed)
    assert loaded.notice_id == notice.notice_id
    assert {:ok, updated} = Notice.update_notice(notice.notice_id, %{"status" => 0}, allowed)
    assert updated.status == 0
    assert :ok = Notice.delete_notices([notice.notice_id], allowed)
  end

  test "dictionary and notice service reads require an explicit authorization context" do
    assert {:error, :authorization_required} = Dictionary.list_dict_types(%{}, [])
    assert {:error, :authorization_required} = Notice.list_notices(%{}, [])
  end

  defp dictionary_permissions do
    [
      "dictionary:read",
      "dictionary:create",
      "dictionary:update",
      "dictionary:delete",
      "dictionary:refresh"
    ]
  end

  defp principal(data_scope, permissions), do: %{data_scope: data_scope, permissions: permissions}
end
