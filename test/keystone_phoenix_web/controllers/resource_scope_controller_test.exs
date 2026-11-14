defmodule KeystonePhoenixWeb.ResourceScopeControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @tag :integration
  test "global resource entries require ALL or TENANT", %{conn: conn} do
    role = insert_role("DEPARTMENT")
    link_permission(role.role_id, "role:read")
    user = insert_user(role.role_id)
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")

    response = get(authorized(conn, tokens.token), "/api/v1/system/role/list")

    assert get_in(json_response(response, 403), ["error", "code"]) == "data_scope_denied"

    Repo.update!(Ecto.Changeset.change(role, data_scope: "TENANT"))
    {:ok, refreshed} = Auth.login_plaintext(user.username, "Strong!123", true)

    response = get(authorized(build_conn(), refreshed.token), "/api/v1/system/role/list")
    assert response.status == 200
    assert json_response(response, 200)["success"] == true
  end

  @tag :integration
  test "non-global scopes reject read, detail, write and delete resource entrances" do
    {token, ids} = authenticated_scope_user("DEPARTMENT")

    for {label, method, path, params} <- operation_cases(ids) do
      response = request(authorized(build_conn(), token), method, path, params)

      assert response.status == 403, "#{label} returned #{response.status}"
      assert json_response(response, 403)["error"]["code"] == "data_scope_denied", label
    end
  end

  @tag :integration
  test "tenant scope passes every non-user resource gate" do
    {token, ids} = authenticated_scope_user("TENANT")

    for {label, path, params} <- list_cases(ids) do
      response = get(authorized(build_conn(), token), path, params)

      refute data_scope_denied?(response), "#{label} was rejected by the resource scope gate"
    end
  end

  @tag :integration
  test "owner-scoped file upload uses the authenticated user namespace" do
    directory =
      Path.join(System.tmp_dir!(), "keystone-http-upload-#{System.unique_integer([:positive])}")

    old_directory = Application.get_env(:keystone_phoenix, :file_base_dir)
    Application.put_env(:keystone_phoenix, :file_base_dir, directory)

    on_exit(fn ->
      if old_directory,
        do: Application.put_env(:keystone_phoenix, :file_base_dir, old_directory),
        else: Application.delete_env(:keystone_phoenix, :file_base_dir)

      File.rm_rf!(directory)
    end)

    {token, ids} = authenticated_scope_user("TENANT")

    source =
      Path.join(
        System.tmp_dir!(),
        "keystone-http-upload-#{System.unique_integer([:positive])}.txt"
      )

    File.write!(source, "http upload")
    on_exit(fn -> File.rm(source) end)

    upload = %Plug.Upload{path: source, filename: "http.txt", content_type: "text/plain"}
    response = post(authorized(build_conn(), token), "/api/v1/file/upload", %{"file" => upload})

    assert %{"data" => %{"newFileName" => filename, "url" => url}} = json_response(response, 200)
    assert url == "/profile/upload/#{ids.user_id}/#{filename}"
    assert File.exists?(Path.join([directory, "upload", ids.user_id, filename]))
  end

  @tag :integration
  test "owner-scoped multipart batch upload stores every file in the owner namespace" do
    directory =
      Path.join(
        System.tmp_dir!(),
        "keystone-http-batch-upload-#{System.unique_integer([:positive])}"
      )

    old_directory = Application.get_env(:keystone_phoenix, :file_base_dir)
    Application.put_env(:keystone_phoenix, :file_base_dir, directory)

    on_exit(fn ->
      if old_directory,
        do: Application.put_env(:keystone_phoenix, :file_base_dir, old_directory),
        else: Application.delete_env(:keystone_phoenix, :file_base_dir)

      File.rm_rf!(directory)
    end)

    {token, ids} = authenticated_scope_user("TENANT")

    sources =
      Enum.map([{"first.txt", "first file"}, {"second.pdf", "second file"}], fn {filename, body} ->
        path = Path.join(System.tmp_dir!(), "keystone-http-#{System.unique_integer([:positive])}")
        File.write!(path, body)
        on_exit(fn -> File.rm(path) end)
        %Plug.Upload{path: path, filename: filename, content_type: "application/octet-stream"}
      end)

    response =
      post(authorized(build_conn(), token), "/api/v1/file/uploads", %{"files" => sources})

    assert %{"data" => stored} = json_response(response, 200)
    assert length(stored) == 2

    Enum.each(stored, fn %{"url" => url, "newFileName" => filename} ->
      assert String.starts_with?(url, "/profile/upload/#{ids.user_id}/")
      assert File.exists?(Path.join([directory, "upload", ids.user_id, filename]))
    end)
  end

  @tag :integration
  test "owner job and notice HTTP commands filter and roll back mixed deletes" do
    {owner_token, _owner_ids} = authenticated_scope_user("OWNER")
    {other_token, _other_ids} = authenticated_scope_user("OWNER")
    job_name = "owner_http_job_#{System.unique_integer([:positive])}"
    notice_title = "owner_http_notice_#{System.unique_integer([:positive])}"

    assert json_response(
             post(authorized(build_conn(), owner_token), "/api/v1/system/jobs", %{
               "jobName" => job_name,
               "jobGroup" => "owner-http",
               "invokeTarget" => "demoJobTask.printHeartbeat()",
               "cronExpression" => "*/5 * * * * *",
               "concurrent" => 0,
               "status" => 0
             }),
             200
           )["success"]

    assert json_response(
             post(authorized(build_conn(), other_token), "/api/v1/system/jobs", %{
               "jobName" => job_name <> "_other",
               "jobGroup" => "owner-http",
               "invokeTarget" => "demoJobTask.printHeartbeat()",
               "cronExpression" => "*/5 * * * * *",
               "concurrent" => 0,
               "status" => 0
             }),
             200
           )["success"]

    assert json_response(
             post(authorized(build_conn(), owner_token), "/api/v1/system/notices", %{
               "noticeTitle" => notice_title,
               "noticeType" => 1,
               "noticeContent" => "owner http notice",
               "status" => 1
             }),
             201
           )["success"]

    assert json_response(
             post(authorized(build_conn(), other_token), "/api/v1/system/notices", %{
               "noticeTitle" => notice_title <> "_other",
               "noticeType" => 1,
               "noticeContent" => "other owner http notice",
               "status" => 1
             }),
             201
           )["success"]

    owner_job_id = owner_id(owner_token, "/api/v1/system/jobs", %{"jobName" => job_name}, "jobId")

    other_job_id =
      owner_id(other_token, "/api/v1/system/jobs", %{"jobName" => job_name <> "_other"}, "jobId")

    owner_notice_id =
      owner_id(
        owner_token,
        "/api/v1/system/notices",
        %{"noticeTitle" => notice_title},
        "noticeId"
      )

    other_notice_id =
      owner_id(
        other_token,
        "/api/v1/system/notices",
        %{"noticeTitle" => notice_title <> "_other"},
        "noticeId"
      )

    assert %{
             "success" => true,
             "data" => %{"rows" => [%{"jobId" => ^owner_job_id}], "total" => 1}
           } =
             json_response(
               get(authorized(build_conn(), owner_token), "/api/v1/system/jobs", %{
                 "jobName" => "owner_http_job"
               }),
               200
             )

    assert %{
             "success" => true,
             "data" => %{"rows" => [%{"noticeId" => ^owner_notice_id}], "total" => 1}
           } =
             json_response(
               get(authorized(build_conn(), owner_token), "/api/v1/system/notices", %{
                 "noticeTitle" => "owner_http_notice"
               }),
               200
             )

    assert json_response(
             get(authorized(build_conn(), owner_token), "/api/v1/system/jobs/#{other_job_id}"),
             404
           )["error"]["code"] == "validation_failed"

    assert json_response(
             get(
               authorized(build_conn(), owner_token),
               "/api/v1/system/notices/#{other_notice_id}"
             ),
             404
           )["error"]["code"] == "validation_failed"

    assert json_response(
             delete(
               authorized(build_conn(), owner_token),
               "/api/v1/system/jobs?jobIds=#{owner_job_id},#{other_job_id}",
               %{}
             ),
             404
           )["error"]["code"] == "validation_failed"

    assert json_response(
             delete(
               authorized(build_conn(), owner_token),
               "/api/v1/system/notices?notice_ids=#{owner_notice_id},#{other_notice_id}",
               %{}
             ),
             404
           )["error"]["code"] == "validation_failed"

    assert get(authorized(build_conn(), owner_token), "/api/v1/system/jobs/#{owner_job_id}").status ==
             200

    assert get(authorized(build_conn(), owner_token), "/api/v1/system/notices/#{owner_notice_id}").status ==
             200
  end

  @tag :integration
  test "export endpoints enforce scope and render an authorized workbook" do
    export_cases = export_cases()
    {department_token, _ids} = authenticated_scope_user("DEPARTMENT")

    for {label, method, path} <- export_cases do
      response = request(authorized(build_conn(), department_token), method, path, %{})

      assert response.status == 403, "#{label} returned #{response.status}"
      assert json_response(response, 403)["error"]["code"] == "data_scope_denied", label
    end

    {tenant_token, _ids} = authenticated_scope_user("TENANT")

    for {label, method, path} <- export_cases do
      response = request(authorized(build_conn(), tenant_token), method, path, %{})

      assert response.status == 200, "#{label} returned #{response.status}"

      assert [content_type] = get_resp_header(response, "content-type")

      assert String.starts_with?(
               content_type,
               "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
             )

      assert byte_size(response.resp_body) > 100, label
    end
  end

  defp authorized(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp authenticated_scope_user(data_scope) do
    permissions = resource_permissions()
    role = insert_role(data_scope)
    Enum.each(permissions, &link_permission(role.role_id, &1))
    user = insert_user(role.role_id)
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")

    ids = %{
      uuid: Identity.v7(),
      file_name: "missing-scope-#{System.unique_integer([:positive])}.txt",
      user_id: user.user_id
    }

    {tokens.token, ids}
  end

  defp resource_permissions do
    ~w(
      role:read role:export
      post:read post:export post:create post:update post:delete
      menu:read menu:create menu:update menu:delete
      config:read config:create config:update config:refresh
      dictionary:read dictionary:create dictionary:update dictionary:delete dictionary:refresh
      login-log:read login-log:export login-log:delete
      operation-log:read operation-log:export operation-log:delete
      cache:refresh server:read online-session:read online-session:revoke
      job:read job:create job:update job:update-status job:run job:delete
      notice:read notice:create notice:update notice:delete
      file:read file:write
    )
  end

  defp operation_cases(%{uuid: uuid, file_name: file_name}) do
    [
      {"role export", :post, "/api/v1/system/role/export", %{}},
      {"post list", :get, "/api/v1/system/post/list", %{}},
      {"post detail", :get, "/api/v1/system/post/#{uuid}", %{}},
      {"post write", :post, "/api/v1/system/post", %{}},
      {"post delete", :delete, "/api/v1/system/post?ids=#{uuid}", %{}},
      {"menu list", :get, "/api/v1/system/menus", %{}},
      {"menu detail", :get, "/api/v1/system/menus/#{uuid}", %{}},
      {"menu write", :post, "/api/v1/system/menus", %{}},
      {"menu delete", :delete, "/api/v1/system/menus/#{uuid}", %{}},
      {"config list", :get, "/api/v1/system/configs", %{}},
      {"config detail", :get, "/api/v1/system/config/#{uuid}", %{}},
      {"config write", :post, "/api/v1/system/config", %{}},
      {"config update", :put, "/api/v1/system/config/#{uuid}", %{}},
      {"dictionary list", :get, "/api/v1/system/dict/types", %{}},
      {"dictionary detail", :get, "/api/v1/system/dict/type/#{uuid}", %{}},
      {"dictionary write", :post, "/api/v1/system/dict/type", %{}},
      {"dictionary delete", :delete, "/api/v1/system/dict/type/#{uuid}", %{}},
      {"audit list", :get, "/api/v1/logs/loginLogs", %{}},
      {"audit detail", :get, "/api/v1/logs/operationLogs", %{}},
      {"audit delete", :delete, "/api/v1/logs/loginLogs?ids=#{uuid}", %{}},
      {"session list", :get, "/api/v1/monitor/onlineUsers", %{}},
      {"session detail", :get, "/api/v1/monitor/serverInfo", %{}},
      {"session write", :get, "/api/v1/monitor/cacheInfo", %{}},
      {"session delete", :delete, "/api/v1/monitor/onlineUser/#{uuid}", %{}},
      {"job list", :get, "/api/v1/system/jobs", %{}},
      {"job detail", :get, "/api/v1/system/jobs/#{uuid}", %{}},
      {"job write", :post, "/api/v1/system/jobs", %{}},
      {"job delete", :delete, "/api/v1/system/jobs?jobIds=#{uuid}", %{}},
      {"notice list", :get, "/api/v1/system/notices", %{}},
      {"notice detail", :get, "/api/v1/system/notices/#{uuid}", %{}},
      {"notice write", :post, "/api/v1/system/notices", %{}},
      {"notice delete", :delete, "/api/v1/system/notices?notice_ids=#{uuid}", %{}},
      {"file detail", :get, "/api/v1/file/download?fileName=#{file_name}", %{}},
      {"file write", :post, "/api/v1/file/upload", %{}},
      {"file batch write", :post, "/api/v1/file/uploads", %{}}
    ]
  end

  defp export_cases do
    [
      {"post export", :get, "/api/v1/system/post/excel"},
      {"role export", :post, "/api/v1/system/role/export"},
      {"login log export", :get, "/api/v1/logs/loginLogs/excel"},
      {"operation log export", :get, "/api/v1/logs/operationLogs/excel"}
    ]
  end

  defp owner_id(token, path, params, field) do
    response = get(authorized(build_conn(), token), path, params)

    assert %{"data" => %{"rows" => [%{^field => id}], "total" => 1}} =
             json_response(response, 200)

    id
  end

  defp list_cases(%{file_name: file_name}) do
    [
      {"post", "/api/v1/system/post/list", %{}},
      {"menu", "/api/v1/system/menus", %{}},
      {"config", "/api/v1/system/configs", %{}},
      {"dictionary", "/api/v1/system/dict/types", %{}},
      {"audit", "/api/v1/logs/loginLogs", %{}},
      {"session", "/api/v1/monitor/onlineUsers", %{}},
      {"job", "/api/v1/system/jobs", %{}},
      {"notice", "/api/v1/system/notices", %{}},
      {"file", "/api/v1/file/download?fileName=#{file_name}", %{}}
    ]
  end

  defp request(conn, :get, path, params), do: get(conn, path, params)
  defp request(conn, :post, path, params), do: post(conn, path, params)
  defp request(conn, :put, path, params), do: put(conn, path, params)
  defp request(conn, :delete, path, params), do: delete(conn, path, params)

  defp data_scope_denied?(%Plug.Conn{status: 403} = conn),
    do: json_response(conn, 403)["error"]["code"] == "data_scope_denied"

  defp data_scope_denied?(_conn), do: false

  defp insert_role(data_scope) do
    %SysRole{}
    |> SysRole.changeset(%{
      role_name: "资源范围测试",
      role_key: "resource_scope_#{System.unique_integer([:positive])}",
      role_sort: 1,
      data_scope: data_scope,
      status: 1
    })
    |> Repo.insert!()
  end

  defp link_permission(role_id, permission) do
    entry = Repo.get_by!(SysPermission, permission: permission)

    Repo.insert!(%SysRolePermission{role_id: role_id, permission_id: entry.permission_id})
    PolicyCache.invalidate()
  end

  defp insert_user(role_id) do
    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      role_id: role_id,
      username: "resource_scope_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end
end
