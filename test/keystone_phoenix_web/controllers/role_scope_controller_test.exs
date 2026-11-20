defmodule KeystonePhoenixWeb.RoleScopeControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.User.SysUserRole

  @tag :integration
  test "role permission HTTP replacement updates normalized authorization bindings" do
    actor_role = create_role("TENANT")
    grant_permission(actor_role.role_id, "role:manage")
    target_role = create_role("TENANT")
    actor = create_user(actor_role.role_id)
    token = step_up_token(actor)

    response =
      put(
        authorized(token),
        "/api/v1/roles/#{target_role.role_id}/permissions",
        %{"permissions" => ["user:read", "role:read"]}
      )

    assert %{"success" => true, "data" => %{"updated" => true}} = json_response(response, 200)

    assert Repo.all(
             from(binding in SysRolePermission,
               join: permission in SysPermission,
               on: permission.permission_id == binding.permission_id,
               where: binding.role_id == ^target_role.role_id,
               select: permission.permission,
               order_by: permission.permission
             )
           ) == ["role:read", "user:read"]
  end

  @tag :integration
  test "role user batch HTTP commands roll back mixed targets" do
    actor_role = create_role("TENANT")
    grant_permission(actor_role.role_id, "role:assign")
    target_role = create_role("TENANT")
    source_role = create_role("TENANT")
    actor = create_user(actor_role.role_id)
    target = create_user(source_role.role_id)
    alias_target = create_user(nil)
    missing_id = Identity.v7()
    token = step_up_token(actor)

    assign_path = "/api/v1/roles/#{target_role.role_id}/users"

    deprecated_assign =
      put(authorized(token), assign_path, %{"user_ids" => [alias_target.user_id]})

    assert get_in(json_response(deprecated_assign, 422), ["error", "code"]) ==
             "validation_failed"

    assert Repo.get!(SysUser, alias_target.user_id).role_id == nil

    response =
      put(authorized(token), assign_path, %{"userIds" => [target.user_id, missing_id]})

    assert get_in(json_response(response, 404), ["error", "code"]) == "resource_not_found"
    assert Repo.get!(SysUser, target.user_id).role_id == source_role.role_id

    assert %{"success" => true} =
             json_response(
               put(
                 authorized(token),
                 assign_path,
                 %{"userIds" => [target.user_id]}
               ),
               200
             )

    assert Repo.get!(SysUser, target.user_id).role_id == target_role.role_id

    assert Repo.exists?(
             from(membership in SysUserRole,
               where:
                 membership.user_id == ^target.user_id and
                   membership.role_id == ^source_role.role_id
             )
           )

    unassign_path = "/api/v1/roles/#{target_role.role_id}/users"
    foreign_role = create_role("TENANT")
    foreign_user = create_user(foreign_role.role_id)

    assert %{"success" => true} =
             json_response(
               delete(authorized(token), unassign_path, %{"userIds" => [foreign_user.user_id]}),
               200
             )

    assert Repo.get!(SysUser, foreign_user.user_id).role_id == foreign_role.role_id

    deprecated_revoke =
      delete(authorized(token), unassign_path, %{"user_ids" => [target.user_id]})

    assert get_in(json_response(deprecated_revoke, 422), ["error", "code"]) ==
             "validation_failed"

    assert Repo.get!(SysUser, target.user_id).role_id == target_role.role_id

    assert %{"success" => true} =
             json_response(
               delete(authorized(token), unassign_path, %{"userIds" => [target.user_id]}),
               200
             )

    assert Repo.get!(SysUser, target.user_id).role_id == source_role.role_id

    refute Repo.exists?(
             from(membership in SysUserRole,
               where:
                 membership.user_id == ^target.user_id and
                   membership.role_id == ^target_role.role_id
             )
           )

    assert Repo.exists?(
             from(membership in SysUserRole,
               where:
                 membership.user_id == ^target.user_id and
                   membership.role_id == ^source_role.role_id
             )
           )

    response =
      delete(authorized(token), unassign_path, %{"userIds" => [target.user_id, missing_id]})

    assert get_in(json_response(response, 404), ["error", "code"]) == "resource_not_found"
    assert Repo.get!(SysUser, target.user_id).role_id == source_role.role_id
  end

  @tag :integration
  test "role member HTTP queries return allocated and unallocated users" do
    actor_role = create_role("ALL")
    grant_permission(actor_role.role_id, "role:read")
    grant_permission(actor_role.role_id, "role:assign")
    target_role = create_role("TENANT")
    preferred_role = create_role("TENANT")
    actor = create_user(actor_role.role_id)
    allocated = create_user(preferred_role.role_id)

    Repo.update_all(from(user in SysUser, where: user.user_id == ^allocated.user_id),
      set: [phone_number: nil]
    )

    Repo.insert!(%SysUserRole{user_id: allocated.user_id, role_id: target_role.role_id})
    unallocated = create_user(nil)
    allocated_id = allocated.user_id
    unallocated_id = unallocated.user_id
    token = step_up_token(actor)

    # 查询接口必须通过真实路由返回 UUID 用户记录，并保持筛选条件生效。
    allocated_response =
      get(
        authorized(token),
        "/api/v1/roles/#{target_role.role_id}/users",
        %{"allocated" => "true", "username" => allocated.username}
      )

    assert %{"success" => true, "data" => [^allocated_id]} =
             json_response(allocated_response, 200)

    allocated_identity =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "true",
        "include" => "identity",
        "username" => allocated.username
      })

    assert %{"success" => true, "data" => [identity]} =
             json_response(allocated_identity, 200)

    assert identity == %{
             "id" => allocated_id,
             "username" => allocated.username,
             "displayName" => allocated.nickname
           }

    blank_phone =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "true",
        "phoneNumber" => "   "
      })

    assert %{"data" => [^allocated_id]} = json_response(blank_phone, 200)

    unallocated_response =
      get(
        authorized(token),
        "/api/v1/roles/#{target_role.role_id}/users",
        %{"allocated" => "false", "username" => unallocated.username}
      )

    assert %{"success" => true, "data" => [^unallocated_id]} =
             json_response(unallocated_response, 200)

    unallocated_identity =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "false",
        "include" => "identity",
        "username" => unallocated.username
      })

    assert %{"success" => true, "data" => [identity]} =
             json_response(unallocated_identity, 200)

    assert identity == %{
             "id" => unallocated_id,
             "username" => unallocated.username,
             "displayName" => unallocated.nickname
           }

    non_allocated_response =
      get(
        authorized(token),
        "/api/v1/roles/#{target_role.role_id}/users",
        %{"allocated" => "false", "username" => allocated.username}
      )

    assert %{"success" => true, "data" => []} = json_response(non_allocated_response, 200)

    for role_id <- ["not-a-uuid", Identity.v7()] do
      missing_response = get(authorized(token), "/api/v1/roles/#{role_id}/users")

      assert get_in(json_response(missing_response, 404), ["error", "code"]) ==
               "resource_not_found"
    end

    assert %{"success" => true, "data" => %{"updated" => true}} =
             json_response(
               put(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
                 "userIds" => []
               }),
               200
             )

    assert %{"success" => true, "data" => %{"updated" => true}} =
             json_response(
               delete(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
                 "userIds" => []
               }),
               200
             )
  end

  @tag :integration
  test "role member HTTP queries keep legacy pagination unpaged and support native paging" do
    reader_role = create_role("ALL")
    grant_permission(reader_role.role_id, "role:read")
    target_role = create_role("ALL")
    preferred_role = create_role("ALL")
    actor = create_user(reader_role.role_id)
    token = step_up_token(actor)
    now = DateTime.utc_now()
    identity_filter = "roleScopeFilter#{System.unique_integer([:positive])}"

    allocated_rows =
      for index <- 1..501 do
        %{
          user_id: Identity.v7(),
          username:
            if(index == 1,
              do: identity_filter,
              else: "role_scope_bulk_#{index}_#{System.unique_integer([:positive])}"
            ),
          password: "bulk-test-password",
          role_id: preferred_role.role_id,
          status: 1,
          deleted: false,
          create_time: now,
          update_time: now
        }
      end

    {501, inserted_users} = Repo.insert_all(SysUser, allocated_rows, returning: [:user_id])

    Repo.insert_all(
      SysUserRole,
      Enum.map(inserted_users, &%{user_id: &1.user_id, role_id: target_role.role_id})
    )

    allocated_ids = Enum.map(inserted_users, & &1.user_id)

    unallocated_ids =
      for _ <- 1..12 do
        create_user(nil).user_id
      end

    allocated_response =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "true"
      })

    allocated_result = json_response(allocated_response, 200)
    assert MapSet.new(allocated_result["data"]) == MapSet.new(allocated_ids)

    unallocated_response =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "false"
      })

    unallocated_result = json_response(unallocated_response, 200)
    assert MapSet.subset?(MapSet.new(unallocated_ids), MapSet.new(unallocated_result["data"]))

    identity_response =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "true",
        "include" => "identity",
        "pageNum" => "2",
        "pageSize" => "3"
      })

    identity_rows = json_response(identity_response, 200)["data"]
    assert length(identity_rows) == 501
    assert MapSet.new(Enum.map(identity_rows, & &1["id"])) == MapSet.new(allocated_ids)

    assert Enum.all?(
             identity_rows,
             &(Map.keys(&1) |> Enum.sort() == ["displayName", "id", "username"])
           )

    legacy_ids =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "true",
        "pageNum" => "2",
        "pageSize" => "3"
      })

    assert %{"data" => ids} = json_response(legacy_ids, 200)
    assert length(ids) == 501
    assert MapSet.new(ids) == MapSet.new(allocated_ids)

    explicit_page =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "true",
        "page" => "2",
        "size" => "3"
      })

    explicit_result = json_response(explicit_page, 200)["data"]
    ordered_ids = Enum.sort(allocated_ids, :desc)
    assert explicit_result["page"] == 2
    assert explicit_result["size"] == 3
    assert explicit_result["total"] == 501
    assert explicit_result["items"] == Enum.slice(ordered_ids, 3, 3)

    size_only =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "true",
        "size" => "4"
      })

    size_only_result = json_response(size_only, 200)["data"]
    assert size_only_result["page"] == 1
    assert size_only_result["size"] == 4
    assert size_only_result["total"] == 501
    assert size_only_result["items"] == Enum.take(ordered_ids, 4)

    page_only =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "true",
        "page" => "2"
      })

    page_only_result = json_response(page_only, 200)["data"]
    assert page_only_result["page"] == 2
    assert page_only_result["size"] == 20
    assert page_only_result["total"] == 501
    assert length(page_only_result["items"]) == 20

    normalized_bounds =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "true",
        "page" => "0",
        "size" => "-3"
      })

    normalized_result = json_response(normalized_bounds, 200)["data"]
    assert normalized_result["page"] == 1
    assert normalized_result["size"] == 1
    assert normalized_result["total"] == 501
    assert normalized_result["items"] == Enum.take(ordered_ids, 1)

    overflow_bounds =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "true",
        "page" => "2147483648",
        "size" => "2147483648"
      })

    overflow_result = json_response(overflow_bounds, 200)["data"]
    assert overflow_result["page"] == 1
    assert overflow_result["size"] == 1
    assert overflow_result["total"] == 501
    assert overflow_result["items"] == Enum.take(ordered_ids, 1)

    capped_size =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "true",
        "size" => "101"
      })

    capped_result = json_response(capped_size, 200)["data"]
    assert capped_result["size"] == 100
    assert capped_result["total"] == 501
    assert length(capped_result["items"]) == 100

    unallocated_page =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "false",
        "page" => "1",
        "size" => "1"
      })

    unallocated_result = json_response(unallocated_page, 200)["data"]
    assert unallocated_result["page"] == 1
    assert unallocated_result["size"] == 1
    assert unallocated_result["total"] >= length(unallocated_ids)
    assert length(unallocated_result["items"]) == 1

    filtered_page =
      get(authorized(token), "/api/v1/roles/#{target_role.role_id}/users", %{
        "allocated" => "true",
        "include" => "identity",
        "username" => identity_filter,
        "page" => "1",
        "size" => "10"
      })

    filtered_result = json_response(filtered_page, 200)["data"]
    assert filtered_result["total"] == 1
    assert [%{"id" => _, "username" => username, "displayName" => _}] = filtered_result["items"]
    assert username == identity_filter

    missing_role = get(authorized(token), "/api/v1/roles/#{Identity.v7()}/users")
    assert get_in(json_response(missing_role, 404), ["error", "code"]) == "resource_not_found"

    unprivileged = create_user(nil)
    unprivileged_token = step_up_token(unprivileged)

    denied =
      get(authorized(unprivileged_token), "/api/v1/roles/#{target_role.role_id}/users")

    assert get_in(json_response(denied, 403), ["error", "code"]) == "permission_denied"

    identity_denied =
      get(
        authorized(unprivileged_token),
        "/api/v1/roles/#{target_role.role_id}/users",
        %{
          "include" => "identity"
        }
      )

    assert get_in(json_response(identity_denied, 403), ["error", "code"]) == "permission_denied"
  end

  @tag :integration
  test "role batch delete rolls back missing targets and deduplicates IDs" do
    actor_role = create_role("TENANT")
    grant_permission(actor_role.role_id, "role:delete")
    first_role = create_role("TENANT")
    second_role = create_role("TENANT")
    missing_id = Identity.v7()
    actor = create_user(actor_role.role_id)
    token = step_up_token(actor)

    rejected =
      delete(
        authorized(token),
        "/api/v1/roles",
        %{"ids" => Enum.join([first_role.role_id, missing_id, second_role.role_id], ",")}
      )

    assert get_in(json_response(rejected, 404), ["error", "code"]) == "resource_not_found"
    assert Repo.get!(SysRole, first_role.role_id).deleted == false
    assert Repo.get!(SysRole, second_role.role_id).deleted == false

    success =
      delete(
        authorized(token),
        "/api/v1/roles",
        %{
          "ids" => Enum.join([first_role.role_id, first_role.role_id, second_role.role_id], ",")
        }
      )

    assert get_in(json_response(success, 200), ["data", "deleted"]) == 2
    assert Repo.get!(SysRole, first_role.role_id).deleted == true
    assert Repo.get!(SysRole, second_role.role_id).deleted == true
  end

  defp authorized(token), do: put_req_header(build_conn(), "authorization", "Bearer #{token}")

  defp create_role(data_scope) do
    %SysRole{}
    |> SysRole.changeset(%{
      role_name: "角色范围 HTTP 测试",
      role_key: "role_scope_http_#{System.unique_integer([:positive])}",
      role_sort: 1,
      data_scope: data_scope,
      status: 1
    })
    |> Repo.insert!()
  end

  defp grant_permission(role_id, permission) do
    permission = Repo.get_by!(SysPermission, permission: permission)
    Repo.insert!(%SysRolePermission{role_id: role_id, permission_id: permission.permission_id})
    PolicyCache.invalidate()
  end

  defp create_user(role_id) do
    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        user_id: Identity.v7(),
        username: "role_scope_http_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        role_id: role_id,
        status: 1
      })
      |> Repo.insert!()

    if role_id, do: Repo.insert!(%SysUserRole{user_id: user.user_id, role_id: role_id})
    user
  end
end
