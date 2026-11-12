defmodule KeystonePhoenix.Authz.PermissionCatalog do
  @moduledoc """
  Stable permission catalog for the canonical policy store.

  The catalog gives writes and audits a common format, metadata shape, and
  duplicate check. Menu navigation references these canonical capabilities.
  """

  @permission_pattern ~r/\A[a-z][a-z0-9_-]*:[a-z][a-z0-9_-]*:[A-Za-z][A-Za-z0-9_-]*\z/

  @permissions ~w(
    monitor:cache:list
    monitor:logininfor:export
    monitor:logininfor:list
    monitor:logininfor:remove
    monitor:online:forceLogout
    monitor:online:list
    monitor:operlog:export
    monitor:operlog:list
    monitor:operlog:remove
    monitor:server:list
    system:config:add
    system:config:edit
    system:config:list
    system:config:query
    system:config:refresh
    system:dept:add
    system:dept:edit
    system:dept:list
    system:dept:query
    system:dept:remove
    system:dict:add
    system:dict:edit
    system:dict:list
    system:dict:query
    system:dict:refresh
    system:dict:remove
    system:file:download
    system:file:upload
    system:job:add
    system:job:changeStatus
    system:job:edit
    system:job:list
    system:job:query
    system:job:remove
    system:job:run
    system:menu:add
    system:menu:edit
    system:menu:list
    system:menu:permission
    system:menu:query
    system:menu:remove
    system:notice:add
    system:notice:edit
    system:notice:list
    system:notice:query
    system:notice:remove
    system:post:add
    system:post:edit
    system:post:export
    system:post:list
    system:post:query
    system:post:remove
    system:role:add
    system:role:edit
    system:role:export
    system:role:list
    system:role:permission
    system:role:query
    system:role:remove
    system:user:add
    system:user:edit
    system:user:export
    system:user:import
    system:user:list
    system:user:query
    system:user:remove
    system:user:resetPwd
  )

  @doc "Returns every permission registered in the canonical catalog."
  def permissions, do: @permissions

  @doc "Returns metadata for every registered permission."
  def entries, do: Enum.map(@permissions, &metadata!/1)

  @doc "Normalizes a permission string without changing its case-sensitive action."
  def normalize(permission) when is_binary(permission), do: String.trim(permission)
  def normalize(_permission), do: ""

  @doc "Checks the stable `resource:domain:action` permission format."
  def valid?(permission) when is_binary(permission),
    do: Regex.match?(@permission_pattern, normalize(permission))

  def valid?(_permission), do: false

  @doc "Validates one permission and returns normalized metadata."
  def validate(permission) do
    normalized = normalize(permission)

    cond do
      normalized == "" -> {:error, :empty_permission}
      not valid?(normalized) -> {:error, :invalid_permission}
      normalized in @permissions -> {:ok, metadata!(normalized)}
      true -> {:ok, metadata(normalized, false)}
    end
  end

  @doc "Checks a permission list for malformed or duplicate entries."
  def validate_catalog(permissions) when is_list(permissions) do
    normalized = Enum.map(permissions, &normalize/1)
    duplicates = normalized -- Enum.uniq(normalized)
    invalid = Enum.reject(normalized, &valid?/1)

    if duplicates == [] and invalid == [],
      do: {:ok, Enum.map(normalized, &metadata(&1, &1 in @permissions))},
      else: {:error, %{duplicates: Enum.uniq(duplicates), invalid: Enum.uniq(invalid)}}
  end

  def validate_catalog(_permissions), do: {:error, %{duplicates: [], invalid: [:not_a_list]}}

  @doc "Returns metadata for a known or format-valid permission."
  def metadata(permission, registered? \\ nil) do
    normalized = normalize(permission)
    [resource, domain, action] = String.split(normalized, ":", parts: 3)

    %{
      permission: normalized,
      resource: resource,
      domain: domain,
      action: action,
      description: "#{resource} #{domain} #{action}",
      risk: risk(action),
      deprecated: false,
      registered?: registered? == true or normalized in @permissions
    }
  end

  defp metadata!(permission), do: metadata(permission, true)

  defp risk(action) when action in ["remove", "resetPwd", "forceLogout"], do: :high
  defp risk(action) when action in ["add", "edit", "changeStatus", "run"], do: :medium
  defp risk(_action), do: :low
end
