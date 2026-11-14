defmodule KeystonePhoenix.PostScopeTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Post

  test "service commands reject a non-global post scope before database access" do
    principal =
      principal("DEPARTMENT", ["post:read", "post:create", "post:update", "post:delete"])

    authorization = [authorization: %{principal: principal}]

    assert {:error, :data_scope_denied} = Post.list_posts(%{}, authorization)
    assert {:error, :data_scope_denied} = Post.get_post(Identity.v7(), authorization)

    assert {:error, :data_scope_denied} =
             Post.create_post(%{"postCode" => "blocked", "postName" => "越界岗位"}, authorization)

    assert {:error, :data_scope_denied} =
             Post.update_post(Identity.v7(), %{"postName" => "越界修改"}, authorization)

    assert {:error, :data_scope_denied} = Post.delete_posts([Identity.v7()], authorization)
  end

  test "service queries and commands accept a tenant-scoped principal" do
    principal =
      principal("TENANT", ["post:read", "post:create", "post:update", "post:delete"])

    authorization = [authorization: %{principal: principal}]

    assert {:ok, post} =
             Post.create_post(
               %{
                 "postCode" => "scope_#{System.unique_integer([:positive])}",
                 "postName" => "范围岗位"
               },
               authorization
             )

    assert {:ok, page} = Post.list_posts(%{"postName" => "范围岗位"}, authorization)
    assert Enum.any?(page.rows, &(&1["postId"] == post.post_id))

    assert {:ok, loaded} = Post.get_post(post.post_id, authorization)
    assert loaded.post_id == post.post_id

    assert {:ok, updated} =
             Post.update_post(post.post_id, %{"postName" => "范围岗位已更新"}, authorization)

    assert updated.post_name == "范围岗位已更新"
    assert :ok = Post.delete_posts([post.post_id], authorization)
  end

  test "service read requires an explicit authorization context" do
    assert {:error, :authorization_required} = Post.list_posts(%{}, [])
    assert {:error, :authorization_required} = Post.get_post(Identity.v7(), [])
  end

  defp principal(data_scope, permissions) do
    %{data_scope: data_scope, permissions: permissions}
  end
end
