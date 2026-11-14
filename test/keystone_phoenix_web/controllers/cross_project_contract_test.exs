defmodule KeystonePhoenixWeb.CrossProjectContractTest do
  @moduledoc """
  固定 Phoenix 与 Keystone Native 共用的接口字段、权限代码和错误分类。

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
    invalid_credential
    permission_denied
    data_scope_denied
    session_revoked
    authorization_unavailable
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

  test "role permissions use namespaced permission codes" do
    assert {:ok, %{permission: "role:manage", registered?: true}} =
             PermissionCatalog.validate(" role:manage ")

    assert {:ok, %{permission: "user:read", registered?: true}} =
             PermissionCatalog.validate("user:read")

    assert {:error, :invalid_permission} = PermissionCatalog.validate("1001")

    assert {:error, %{invalid: ["1001"], duplicates: []}} =
             PermissionCatalog.validate_catalog(["role:manage", "1001"])
  end

  test "error categories and role permission route stay registered" do
    assert Enum.sort(ApiResponse.error_codes()) == Enum.sort(@error_codes)

    assert Enum.any?(Router.__routes__(), fn route ->
             route.verb == :put and route.path == @role_permission_path
           end)
  end
end
