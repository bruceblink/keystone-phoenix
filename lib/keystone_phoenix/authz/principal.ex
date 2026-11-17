defmodule KeystonePhoenix.Authz.Principal do
  @moduledoc """
  Normalized authorization subject used by `KeystonePhoenix.Authz`.

  The principal keeps normalized identity, role and permission values. Admin
  capability comes only from the catalog permission `permission:manage`.
  """

  alias KeystonePhoenix.User.RoleMembership

  @enforce_keys []
  defstruct subject_id: nil,
            scope_subject_id: nil,
            subject_type: "USER",
            credential_type: "PASSWORD",
            credential_id: nil,
            roles: [],
            tenant_id: nil,
            department_id: nil,
            session_id: nil,
            client_id: nil,
            permissions: nil,
            approved_scopes: [],
            data_scope: nil,
            permission_version: nil,
            authentication_level: "AAL1",
            raw: %{}

  @type t :: %__MODULE__{
          subject_id: term(),
          scope_subject_id: term(),
          subject_type: String.t() | nil,
          credential_type: String.t() | nil,
          credential_id: term(),
          roles: list(),
          tenant_id: term(),
          department_id: term(),
          session_id: term(),
          client_id: term(),
          permissions: list() | nil,
          approved_scopes: list(),
          data_scope: String.t() | nil,
          permission_version: integer() | nil,
          authentication_level: String.t() | nil,
          raw: map()
        }

  @doc "Builds a normalized principal from a domain or API user map."
  @spec from_user(map() | t()) :: t()
  def from_user(%__MODULE__{} = principal), do: principal

  def from_user(user) when is_map(user) do
    credential_type = credential_type(user)
    session_id = value(user, :session_id, "sessionId")
    user_id = value(user, :user_id, "userId")
    subject_id = value(user, :subject_id, "subjectId") || user_id

    scope_subject_id =
      if credential_type == "API_KEY", do: user_id, else: user_id || subject_id

    %__MODULE__{
      subject_id: subject_id,
      scope_subject_id: scope_subject_id,
      subject_type: value(user, :subject_type, "subjectType") || subject_type(credential_type),
      credential_type: credential_type,
      credential_id: credential_id(user, credential_type, session_id),
      roles: roles(user),
      tenant_id: value(user, :tenant_id, "tenantId"),
      department_id: value(user, :dept_id, "deptId"),
      session_id: session_id,
      client_id: value(user, :client_id, "clientId"),
      permissions: permissions(user),
      approved_scopes: approved_scopes(user),
      data_scope: value(user, :data_scope, "dataScope"),
      permission_version: value(user, :permission_version, "permissionVersion"),
      authentication_level: authentication_level(user),
      raw: user
    }
  end

  def from_user(_user), do: %__MODULE__{}

  @doc "Returns the original user map used by the legacy policy adapter."
  @spec to_user(map() | t()) :: map()
  def to_user(%__MODULE__{raw: raw}) when is_map(raw) and map_size(raw) > 0, do: raw

  def to_user(%__MODULE__{} = principal) do
    %{
      user_id: scope_subject_id(principal),
      subject_id: principal.subject_id,
      scope_subject_id: scope_subject_id(principal),
      role_id: List.first(principal.roles),
      tenant_id: principal.tenant_id,
      dept_id: principal.department_id,
      session_id: principal.session_id,
      client_id: principal.client_id,
      permissions: principal.permissions,
      approved_scopes: principal.approved_scopes,
      data_scope: principal.data_scope,
      permission_version: principal.permission_version,
      authentication_level: principal.authentication_level,
      credential_type: principal.credential_type,
      credential_id: principal.credential_id,
      subject_type: principal.subject_type
    }
  end

  def to_user(user) when is_map(user), do: user
  def to_user(_user), do: %{}

  @doc "判断主体是否使用 API Key 认证。"
  @spec api_key?(term()) :: boolean()
  def api_key?(%__MODULE__{credential_type: "API_KEY"}), do: true

  def api_key?(user) when is_map(user) do
    credential_type =
      Map.get(user, :credential_type) ||
        Map.get(user, "credential_type") ||
        Map.get(user, :credentialType) ||
        Map.get(user, "credentialType")

    credential_type == "API_KEY"
  end

  def api_key?(_user), do: false

  @doc "返回数据范围和业务 owner 使用的用户 UUID，API Key 使用其所属用户 ID。"
  @spec scope_subject_id(map() | t() | term()) :: term()
  def scope_subject_id(%__MODULE__{credential_type: "API_KEY", scope_subject_id: id}), do: id

  def scope_subject_id(%__MODULE__{} = principal),
    do: principal.scope_subject_id || principal.subject_id

  def scope_subject_id(user) when is_map(user) do
    from_user(user).scope_subject_id
  end

  def scope_subject_id(_user), do: nil

  @doc "Returns whether a principal has administrator status."
  # API Key scope 只授权具体接口，不授予全局管理员身份。
  def admin?(user) when is_map(user),
    do: not api_key?(user) and "permission:manage" in List.wrap(permissions(user))

  def admin?(_user), do: false

  defp roles(user) do
    case membership_roles(user) do
      [] -> legacy_roles(user)
      role_ids -> role_ids
    end
  end

  # 关联表已存在时优先读取全部角色；旧字段仍作为迁移期间的回退来源。
  defp membership_roles(user) do
    case value(user, :user_id, "userId") do
      user_id when is_binary(user_id) -> RoleMembership.list_role_ids_for_user(user_id)
      _ -> []
    end
  rescue
    _error -> []
  end

  defp legacy_roles(user) do
    case value(user, :role_id, "roleId") do
      nil -> List.wrap(value(user, :roles, "roles"))
      role_id -> [role_id]
    end
  end

  defp permissions(user) do
    value(user, :permissions, "permissions")
  end

  defp approved_scopes(user) do
    value(user, :approved_scopes, "approvedScopes") ||
      value(user, :scopes, "scopes") || []
  end

  defp credential_type(user) do
    value(user, :credential_type, "credentialType") || "PASSWORD"
  end

  defp subject_type("API_KEY"), do: "SERVICE_SUBJECT"
  defp subject_type(_credential_type), do: "USER"

  defp credential_id(user, "PASSWORD", session_id),
    do: value(user, :credential_id, "credentialId") || session_id

  defp credential_id(user, _credential_type, _session_id),
    do: value(user, :credential_id, "credentialId") || value(user, :key_id, "keyId")

  defp authentication_level(user) do
    case value(user, :authentication_level, "authenticationLevel") || value(user, :aal, "aal") do
      value when value in ["AAL1", "AAL2"] -> value
      _value -> "AAL1"
    end
  end

  defp value(user, atom_key, string_key) do
    case Map.get(user, atom_key) do
      nil -> Map.get(user, string_key)
      value -> value
    end
  end
end
