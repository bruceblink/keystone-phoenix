defmodule KeystonePhoenix.SessionFileScopeTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Monitor
  alias KeystonePhoenix.Upload

  setup do
    directory =
      Path.join(System.tmp_dir!(), "keystone-scope-files-#{System.unique_integer([:positive])}")

    old_directory = Application.get_env(:keystone_phoenix, :file_base_dir)
    Application.put_env(:keystone_phoenix, :file_base_dir, directory)

    on_exit(fn ->
      if old_directory,
        do: Application.put_env(:keystone_phoenix, :file_base_dir, old_directory),
        else: Application.delete_env(:keystone_phoenix, :file_base_dir)

      File.rm_rf!(directory)
    end)

    {:ok, directory: directory}
  end

  test "session monitor commands reject a department-scoped principal" do
    permissions = ["cache:refresh", "server:read", "online-session:read", "online-session:revoke"]
    authorization = [authorization: %{principal: principal("DEPARTMENT", permissions)}]

    assert {:error, :data_scope_denied} = Monitor.cache_info(authorization)
    assert {:error, :data_scope_denied} = Monitor.server_info(authorization)
    assert {:error, :data_scope_denied} = Monitor.online_users(%{}, authorization)
    assert {:error, :data_scope_denied} = Monitor.logout_online_user(Identity.v7(), authorization)
    assert {:error, :data_scope_denied} = Monitor.network_status(authorization)
  end

  test "session monitor commands accept a tenant-scoped principal" do
    permissions = ["cache:refresh", "server:read", "online-session:read", "online-session:revoke"]
    authorization = [authorization: %{principal: principal("TENANT", permissions)}]

    assert {:ok, _cache} = Monitor.cache_info(authorization)
    assert {:ok, _server} = Monitor.server_info(authorization)
    assert {:ok, _sessions} = Monitor.online_users(%{}, authorization)
    assert %{"status" => "ONLINE"} = Monitor.network_status(authorization)
    assert {:error, :not_found} = Monitor.logout_online_user(Identity.v7(), authorization)
  end

  test "file service commands enforce file scope and safe download paths", %{directory: directory} do
    permissions = ["file:read", "file:write"]
    blocked = [authorization: %{principal: principal("DEPARTMENT", permissions)}]
    owner_id = Identity.v7()
    other_owner_id = Identity.v7()
    allowed = [authorization: %{principal: principal("TENANT", permissions, owner_id)}]
    upload_path = temporary_file("scope.txt", "scope data")
    upload = %Plug.Upload{path: upload_path, filename: "scope.txt", content_type: "text/plain"}

    assert {:error, :data_scope_denied} = Upload.store_file(upload, owner_id, blocked)
    assert {:error, :data_scope_denied} = Upload.store_files([upload], nil, blocked)
    assert {:error, :data_scope_denied} = Upload.store_file(upload, other_owner_id, allowed)
    assert {:error, :data_scope_denied} = Upload.store_files([upload], other_owner_id, allowed)
    assert {:error, :data_scope_denied} = Upload.resolve_download_path("../secret.txt", blocked)

    assert {:ok, stored} = Upload.store_file(upload, owner_id, allowed)
    assert File.exists?(Path.join([directory, "upload", owner_id, stored["newFileName"]]))

    download = Path.join([directory, "download", "report.txt"])
    File.mkdir_p!(Path.dirname(download))
    File.write!(download, "report")
    assert {:ok, ^download} = Upload.resolve_download_path("report.txt", allowed)
    assert {:error, :invalid_file_name} = Upload.resolve_download_path("../secret.txt", allowed)

    File.rm!(upload_path)
  end

  test "session and file service calls require explicit authorization contexts" do
    assert {:error, :authorization_required} = Monitor.cache_info([])
    assert {:error, :authorization_required} = Monitor.online_users(%{}, [])
    assert {:error, :authorization_required} = Upload.resolve_download_path("report.txt", [])
  end

  defp principal(data_scope, permissions, user_id \\ nil) do
    %{data_scope: data_scope, permissions: permissions}
    |> maybe_put_user_id(user_id)
  end

  defp maybe_put_user_id(principal, nil), do: principal
  defp maybe_put_user_id(principal, user_id), do: Map.put(principal, :user_id, user_id)

  defp temporary_file(filename, content) do
    path =
      Path.join(
        System.tmp_dir!(),
        "keystone-scope-#{System.unique_integer([:positive])}-#{filename}"
      )

    File.write!(path, content)
    path
  end
end
