defmodule KeystonePhoenixWeb.PostBatchControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Post.SysPost
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @tag :integration
  test "post batch delete rolls back when one id is missing" do
    role = insert_role()
    actor = insert_user(role.role_id)
    {:ok, tokens} = Auth.login_plaintext(actor.username, "Strong!123")

    first = create_post(tokens.token, "batch_first")
    second = create_post(tokens.token, "batch_second")
    missing_id = Identity.v7()

    response =
      delete(
        authorized(build_conn(), tokens.token),
        "/api/v1/system/post?ids=#{first.post_id},#{missing_id}",
        %{}
      )

    assert response.status == 404
    assert json_response(response, 404)["error"]["code"] == "validation_failed"
    assert Repo.get!(SysPost, first.post_id).deleted == false
    assert Repo.get!(SysPost, second.post_id).deleted == false

    response =
      delete(
        authorized(build_conn(), tokens.token),
        "/api/v1/system/post?ids=#{first.post_id}",
        %{}
      )

    assert json_response(response, 200)["success"] == true
    assert Repo.get!(SysPost, first.post_id).deleted == true
    assert Repo.get!(SysPost, second.post_id).deleted == false
  end

  defp authorized(conn, token),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")

  defp insert_role do
    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: "岗位批量删除测试",
        role_key: "post_batch_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: "TENANT",
        status: 1
      })
      |> Repo.insert!()

    for permission <- ~w(post:read post:create post:delete) do
      permission = Repo.get_by!(SysPermission, permission: permission)

      Repo.insert!(%SysRolePermission{
        role_id: role.role_id,
        permission_id: permission.permission_id
      })
    end

    PolicyCache.invalidate()
    role
  end

  defp insert_user(role_id) do
    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      role_id: role_id,
      username: "post_batch_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end

  defp create_post(token, prefix) do
    code = "#{prefix}_#{System.unique_integer([:positive])}"

    response =
      post(authorized(build_conn(), token), "/api/v1/system/post", %{
        "postCode" => code,
        "postName" => "#{prefix}岗位",
        "postSort" => 1,
        "status" => 1
      })

    assert response.status == 201
    Repo.get_by!(SysPost, post_code: code)
  end
end
