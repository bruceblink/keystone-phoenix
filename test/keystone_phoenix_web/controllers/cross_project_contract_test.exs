defmodule KeystonePhoenixWeb.CrossProjectContractTest do
  @moduledoc """
  固定 Phoenix、Keystone Native 和 admin-web 共用的接口字段、权限代码和错误分类。

  本测试只检查外部接口约定。它不复制业务实现，也不依赖数据库状态。
  """

  use ExUnit.Case, async: true

  alias KeystonePhoenix.Authz.PermissionCatalog
  alias KeystonePhoenixWeb.ApiResponse
  alias KeystonePhoenixWeb.AuthTokenResponse
  alias KeystonePhoenixWeb.Router

  @token_fields ~w(
    accessToken
    refreshToken
    tokenType
    expiresIn
    refreshExpiresIn
    username
    displayName
    roles
    sessionId
    clientId
  )

  @error_codes ~w(
    active_session_conflict
    api_key_expiry_invalid
    api_key_expiry_out_of_range
    api_key_expired
    api_key_scope_unavailable
    api_key_name_invalid
    api_key_page_changed
    profile_display_name_required
    profile_avatar_required
    authentication_required
    authorization_unavailable
    data_scope_denied
    https_required
    invalid_credential
    internal_error
    mfa_challenge_invalid
    mfa_invalid_code
    mfa_required
    mfa_step_up_required
    mfa_state_conflict
    notice_type_invalid
    permission_denied
    payload_too_large
    password_contains_username
    password_disallowed
    password_missing_digit
    password_missing_lowercase
    password_missing_special
    password_missing_uppercase
    password_required
    password_same_as_current
    password_too_short
    precondition_required
    rate_limited
    resource_conflict
    resource_not_found
    role_has_members
    role_protected
    session_revoked
    service_unavailable
    username_already_exists
    username_invalid_format
    validation_failed
  )

  @role_permission_path "/api/v1/roles/:role_id/permissions"

  test "token response keeps the shared fields and removes legacy aliases" do
    response =
      AuthTokenResponse.to_map(%{
        token: "access-token",
        refresh_token: "refresh-token",
        expires_in: 300,
        refresh_expires_in: 1_209_600,
        session_id: "01j00000-0000-7000-8000-000000000001",
        client_id: "web"
      })

    assert Map.keys(response) |> Enum.sort() == Enum.sort(@token_fields)
    assert response["tokenType"] == "Bearer"
    assert response["expiresIn"] > 0
    assert response["refreshExpiresIn"] > response["expiresIn"]
    refute Map.has_key?(response, "token")
    refute Map.has_key?(response, "currentUser")
  end

  test "token response preserves all role keys and filters invalid entries" do
    response =
      AuthTokenResponse.to_map(%{
        token: "access-token",
        refresh_token: "refresh-token",
        expires_in: 300,
        refresh_expires_in: 1_209_600,
        session_id: "01j00000-0000-7000-8000-000000000001",
        current_user: %{
          "roleKey" => "operator",
          "roles" => ["operator", "auditor", "", "operator", 1]
        }
      })

    assert response["roles"] == ["operator", "auditor"]
  end

  test "role permissions use namespaced permission codes" do
    assert {:ok, %{permission: "role:manage", registered?: true}} =
             PermissionCatalog.validate(" role:manage ")

    assert {:ok, %{permission: "user:read", registered?: true}} =
             PermissionCatalog.validate("user:read")

    assert {:error, :invalid_permission} = PermissionCatalog.validate("1001")

    assert {:error, %{invalid: ["1001"], duplicates: []}} =
             PermissionCatalog.validate_catalog(["role:manage", "1001"])
  end

  test "shared error categories and role permission route stay registered" do
    assert Enum.sort(ApiResponse.error_codes()) == Enum.sort(@error_codes)

    assert %{status: 422, retryable: false, message_key: "role.has_members"} =
             ApiResponse.error_metadata(:role_has_members)

    assert %{status: 422, retryable: false, message_key: "role.protected"} =
             ApiResponse.error_metadata(:role_protected)

    assert Enum.any?(Router.__routes__(), fn route ->
             route.verb == :put and route.path == @role_permission_path
           end)

    assert Enum.any?(Router.__routes__(), fn route ->
             route.verb == :get and route.path == "/api/v1/permissions/catalog"
           end)
  end
end
