defmodule KeystonePhoenixWeb.ApiKeyOwnerScopeTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenix.Auth.ApiKey.ServiceSubject
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Log.SysOperationLog
  alias KeystonePhoenix.RateLimiter
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @owner_permissions ~w(
    job:create job:read job:update job:update-status job:run job:delete
    notice:create notice:read notice:update notice:delete
  )

  @tag :integration
  # 通过真实 HTTP 请求和 PostgreSQL 外键验证 API Key 与所属用户共享业务数据范围。
  test "API Key and owner user share job and notice records while other owners stay isolated", %{
    conn: conn
  } do
    role = create_role("OWNER", @owner_permissions)
    owner = create_user(role, "owner")
    other = create_user(role, "other")
    owner_token = login(owner)
    other_token = login(other)

    assert {:ok, issued} =
             ApiKey.issue(owner.user_id, "owner HTTP test", @owner_permissions)

    assert {:ok, api_principal} = ApiKey.authenticate(issued.api_key)
    assert api_principal.user_id == owner.user_id
    refute api_principal.subject_id == owner.user_id

    human_job = create_job(conn, {:bearer, owner_token}, "human_job")
    human_notice = create_notice(conn, {:bearer, owner_token}, "human_notice")
    other_job = create_job(conn, {:bearer, other_token}, "other_job")
    other_notice = create_notice(conn, {:bearer, other_token}, "other_notice")

    RateLimiter.delete("repeat:/api/v1/notices:create:#{owner.user_id}")
    key_job = create_job(conn, {:api_key, issued.api_key}, "key_job")
    key_notice = create_notice(conn, {:api_key, issued.api_key}, "key_notice")

    assert owner_jobs = list_jobs(conn, {:bearer, owner_token})
    assert key_jobs = list_jobs(conn, {:api_key, issued.api_key})
    assert Enum.sort(Enum.map(owner_jobs, & &1["id"])) == Enum.sort([human_job, key_job])
    assert Enum.sort(Enum.map(key_jobs, & &1["id"])) == Enum.sort([human_job, key_job])

    assert owner_notices = list_notices(conn, {:bearer, owner_token})
    assert key_notices = list_notices(conn, {:api_key, issued.api_key})

    assert Enum.sort(Enum.map(owner_notices, & &1["id"])) ==
             Enum.sort([human_notice, key_notice])

    assert Enum.sort(Enum.map(key_notices, & &1["id"])) ==
             Enum.sort([human_notice, key_notice])

    assert Enum.map(list_jobs(conn, {:bearer, other_token}), & &1["id"]) == [other_job]
    assert Enum.map(list_notices(conn, {:bearer, other_token}), & &1["id"]) == [other_notice]

    assert get(authenticated(conn, {:api_key, issued.api_key}), "/api/v1/jobs/#{other_job}").status ==
             404

    assert get(authenticated(conn, {:api_key, issued.api_key}), "/api/v1/jobs/#{key_job}").status ==
             200

    assert get(authenticated(conn, {:api_key, issued.api_key}), "/api/v1/jobs/#{human_job}").status ==
             200

    assert get(authenticated(conn, {:bearer, owner_token}), "/api/v1/jobs/#{key_job}").status ==
             200

    assert get(authenticated(conn, {:bearer, other_token}), "/api/v1/jobs/#{key_job}").status ==
             404

    assert put(
             authenticated(conn, {:api_key, issued.api_key}),
             "/api/v1/notices/#{human_notice}",
             %{
               "enabled" => false
             }
           ).status == 200

    assert put(authenticated(conn, {:bearer, owner_token}), "/api/v1/notices/#{key_notice}", %{
             "enabled" => false
           }).status == 200

    assert put(authenticated(conn, {:bearer, other_token}), "/api/v1/notices/#{key_notice}", %{
             "enabled" => false
           }).status == 404

    service_subject_id = Repo.get_by!(ServiceSubject, owner_user_id: owner.user_id).id

    assert Repo.get!(KeystonePhoenix.Job.SysJob, human_job).created_by == owner.user_id
    assert Repo.get!(KeystonePhoenix.Job.SysJob, key_job).created_by == owner.user_id
    assert Repo.get!(KeystonePhoenix.Notice.SysNotice, human_notice).owner_id == owner.user_id
    assert Repo.get!(KeystonePhoenix.Notice.SysNotice, key_notice).owner_id == owner.user_id

    decision_log =
      Repo.one!(
        from log in SysOperationLog,
          where:
            log.user_id == ^owner.user_id and log.request_url == "/authz/decision" and
              log.called_method == "job:create" and log.operation_result == "allow",
          order_by: [desc: log.operation_time],
          limit: 1
      )

    assert decision_log.user_id == owner.user_id
    assert Jason.decode!(decision_log.operation_param)["subjectId"] == service_subject_id
  end

  @tag :integration
  test "API Key configuration writes keep the user foreign key and operation audit", %{conn: conn} do
    role = create_role("ALL", ["config:create"])
    owner = create_user(role, "config_owner")

    assert {:ok, issued} = ApiKey.issue(owner.user_id, "config writer", ["config:create"])

    key =
      post(authenticated(conn, {:api_key, issued.api_key}), "/api/v1/configs", %{
        "configName" => "API Key config",
        "configKey" => "api_key_owner_#{System.unique_integer([:positive])}",
        "configValue" => "enabled",
        "isAllowChange" => true
      })

    assert %{"data" => %{"id" => config_id}} = json_response(key, 201)
    config = Repo.get!(KeystonePhoenix.Config.SysConfig, config_id)
    assert config.creator_id == owner.user_id
    assert config.updater_id == nil
  end

  defp create_role(data_scope, permissions) do
    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: "API Key owner scope",
        role_key: "api_key_owner_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: data_scope,
        status: 1
      })
      |> Repo.insert!()

    Enum.each(permissions, fn permission ->
      entry = Repo.get_by!(SysPermission, permission: permission)
      Repo.insert!(%SysRolePermission{role_id: role.role_id, permission_id: entry.permission_id})
    end)

    role
  end

  defp create_user(role, suffix) do
    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      role_id: role.role_id,
      username: "api_key_owner_#{suffix}_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end

  defp login(user) do
    assert {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123", true)
    tokens.token
  end

  defp create_job(conn, identity, suffix) do
    response =
      post(authenticated(conn, identity), "/api/v1/jobs", %{
        "jobName" => "#{suffix}_#{System.unique_integer([:positive])}",
        "jobGroup" => "api-key-owner-scope",
        "invokeTarget" => "demoJobTask.printHeartbeat()",
        "cronExpression" => "*/5 * * * * *",
        "concurrent" => false,
        "status" => 0
      })

    assert %{"data" => %{"id" => id}} = json_response(response, 201)
    id
  end

  defp create_notice(conn, identity, suffix) do
    response =
      post(authenticated(conn, identity), "/api/v1/notices", %{
        "title" => "#{suffix}_#{System.unique_integer([:positive])}",
        "noticeType" => "notification",
        "content" => "owner scope test",
        "enabled" => true
      })

    assert %{"data" => %{"id" => id}} = json_response(response, 201)
    id
  end

  defp list_jobs(conn, identity) do
    conn
    |> authenticated(identity)
    |> get("/api/v1/jobs")
    |> json_response(200)
    |> get_in(["data"])
  end

  defp list_notices(conn, identity) do
    conn
    |> authenticated(identity)
    |> get("/api/v1/notices/manage")
    |> json_response(200)
    |> get_in(["data"])
  end

  defp authenticated(conn, {:bearer, token}),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")

  defp authenticated(conn, {:api_key, value}),
    do: Plug.Conn.put_req_header(conn, "authorization", "ApiKey #{value}")
end
