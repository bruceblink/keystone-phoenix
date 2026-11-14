defmodule KeystonePhoenixWeb.ManagementReadControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @tag :integration
  test "管理员可以通过 HTTP 读取配置、字典和公告管理数据" do
    token = admin_token()
    conn = authorized(build_conn(), token)

    assert %{"success" => true, "data" => %{"rows" => _configs}} =
             json_response(get(conn, "/api/v1/system/configs"), 200)

    assert %{"success" => true, "data" => %{"rows" => _types}} =
             json_response(get(authorized(build_conn(), token), "/api/v1/system/dict/types"), 200)

    assert %{"success" => true, "data" => %{"rows" => _notices}} =
             json_response(get(authorized(build_conn(), token), "/api/v1/system/notices"), 200)
  end

  @tag :integration
  test "字典类型和条目通过 HTTP 创建后可以按类型读取并清理" do
    token = admin_token()
    dict_type = "http.read.#{System.unique_integer([:positive])}"

    type_response =
      post(authorized(build_conn(), token), "/api/v1/system/dict/type", %{
        "dictName" => "HTTP 查询字典",
        "dictType" => dict_type,
        "status" => 1
      })

    assert type_response.status == 201

    type_id =
      get(authorized(build_conn(), token), "/api/v1/system/dict/types", %{
        "dictType" => dict_type
      })
      |> json_response(200)
      |> get_in(["data", "rows", Access.at(0), "dictId"])

    data_response =
      post(authorized(build_conn(), token), "/api/v1/system/dict/data", %{
        "dictType" => dict_type,
        "dictLabel" => "已启用",
        "dictValue" => 1,
        "status" => 1
      })

    assert data_response.status == 201

    assert %{"success" => true, "data" => rows} =
             json_response(
               get(authorized(build_conn(), token), "/api/v1/system/dict/data/type/#{dict_type}"),
               200
             )

    assert Enum.any?(rows, &(&1["dictType"] == dict_type))

    data_code = Enum.find(rows, &(&1["dictType"] == dict_type))["dictCode"]

    assert delete(authorized(build_conn(), token), "/api/v1/system/dict/data/#{data_code}").status ==
             200

    assert delete(authorized(build_conn(), token), "/api/v1/system/dict/type/#{type_id}").status ==
             200
  end

  defp admin_token do
    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: "管理读取测试",
        role_key: "management_read_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: "TENANT",
        status: 1
      })
      |> Repo.insert!()

    for permission <-
          ~w(config:read dictionary:read dictionary:create dictionary:delete notice:read) do
      permission_id = Repo.get_by!(SysPermission, permission: permission).permission_id
      Repo.insert!(%SysRolePermission{role_id: role.role_id, permission_id: permission_id})
    end

    PolicyCache.invalidate()

    user =
      %SysUser{user_id: Identity.v7()}
      |> SysUser.create_changeset(%{
        username: "management_read_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        role_id: role.role_id,
        status: 1
      })
      |> Repo.insert!()

    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    tokens.token
  end

  # 统一使用 Bearer 令牌，确保测试经过真实认证和资源授权入口。
  defp authorized(conn, token),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
end
