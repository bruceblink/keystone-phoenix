defmodule KeystonePhoenix.Authz.PrincipalTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Authz.Principal

  test "normalizes a password session principal with the shared fields" do
    principal =
      Principal.from_user(%{
        user_id: "user-1",
        role_id: "role-1",
        session_id: "session-1",
        client_id: "web",
        permissions: ["user:read"],
        approved_scopes: ["user:read"],
        data_scope: "TENANT",
        permission_version: 4,
        authentication_level: "AAL2"
      })

    assert principal.subject_id == "user-1"
    assert principal.subject_type == "USER"
    assert principal.credential_type == "PASSWORD"
    assert principal.credential_id == "session-1"
    assert principal.session_id == "session-1"
    assert principal.client_id == "web"
    assert principal.approved_scopes == ["user:read"]
    assert principal.data_scope == "TENANT"
    assert principal.permission_version == 4
    assert principal.authentication_level == "AAL2"
  end

  test "keeps service subject and API key identity separate from the owner user" do
    principal =
      Principal.from_user(%{
        subject_id: "service-1",
        subject_type: "SERVICE_SUBJECT",
        user_id: "user-1",
        credential_id: "key-1",
        credential_type: "API_KEY",
        role_id: "role-1",
        approved_scopes: ["user:read"],
        permissions: ["user:read"]
      })

    assert principal.subject_id == "service-1"
    assert principal.subject_type == "SERVICE_SUBJECT"
    assert principal.credential_type == "API_KEY"
    assert principal.credential_id == "key-1"
    assert principal.roles == ["role-1"]
    assert principal.approved_scopes == ["user:read"]
    assert Principal.to_user(principal).subject_type == "SERVICE_SUBJECT"
  end
end
