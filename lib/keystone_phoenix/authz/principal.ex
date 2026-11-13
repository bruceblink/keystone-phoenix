defmodule KeystonePhoenix.Authz.Principal do
  @moduledoc """
  Normalized authorization subject used by `KeystonePhoenix.Authz`.

  The principal keeps normalized identity, role and permission values. The
  legacy `is_admin` field is retained only as an inert transport field until
  the user schema migration removes it; authorization never reads it.
  """

  @enforce_keys []
  defstruct subject_id: nil,
            roles: [],
            is_admin: false,
            tenant_id: nil,
            department_id: nil,
            session_id: nil,
            permissions: nil,
            raw: %{}

  @type t :: %__MODULE__{
          subject_id: term(),
          roles: list(),
          is_admin: boolean(),
          tenant_id: term(),
          department_id: term(),
          session_id: term(),
          permissions: list() | nil,
          raw: map()
        }

  @doc "Builds a normalized principal from a domain or API user map."
  @spec from_user(map() | t()) :: t()
  def from_user(%__MODULE__{} = principal), do: principal

  def from_user(user) when is_map(user) do
    %__MODULE__{
      subject_id: value(user, :user_id, "userId"),
      roles: roles(user),
      is_admin: false,
      tenant_id: value(user, :tenant_id, "tenantId"),
      department_id: value(user, :dept_id, "deptId"),
      session_id: value(user, :session_id, "sessionId"),
      permissions: permissions(user),
      raw: user
    }
  end

  def from_user(_user), do: %__MODULE__{}

  @doc "Returns the original user map used by the legacy policy adapter."
  @spec to_user(map() | t()) :: map()
  def to_user(%__MODULE__{raw: raw}) when is_map(raw) and map_size(raw) > 0, do: raw

  def to_user(%__MODULE__{} = principal) do
    %{
      user_id: principal.subject_id,
      role_id: List.first(principal.roles),
      is_admin: principal.is_admin,
      tenant_id: principal.tenant_id,
      dept_id: principal.department_id,
      session_id: principal.session_id
    }
  end

  def to_user(user) when is_map(user), do: user
  def to_user(_user), do: %{}

  @doc "Returns whether a principal has administrator status."
  def admin?(%__MODULE__{permissions: permissions}) when is_list(permissions),
    do: "permission:manage" in permissions

  def admin?(user) when is_map(user), do: "permission:manage" in List.wrap(permissions(user))
  def admin?(_user), do: false

  defp roles(user) do
    case value(user, :role_id, "roleId") do
      nil -> List.wrap(value(user, :roles, "roles"))
      role_id -> [role_id]
    end
  end

  defp permissions(user) do
    value(user, :permissions, "permissions")
  end

  defp value(user, atom_key, string_key) do
    case Map.get(user, atom_key) do
      nil -> Map.get(user, string_key)
      value -> value
    end
  end
end
