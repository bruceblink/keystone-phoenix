defmodule KeystonePhoenix.Authz.PermissionCatalog do
  @moduledoc """
  定义新系统唯一的权限目录。

  权限使用 `resource:action` 两段格式。菜单只保存展示关系，不能生成权限。
  目录中的权限 ID 由固定 UUIDv5 命名规则生成。
  """

  @permission_pattern ~r/\A[a-z][a-z0-9-]*:[a-z][a-z0-9-]*\z/

  @permissions ~w(
    api-key:create
    api-key:read
    api-key:revoke
    api-key:rotate
    audit:delete
    audit:export
    audit:read
    cache:refresh
    config:create
    config:read
    config:refresh
    config:update
    department:create
    department:delete
    department:read
    department:update
    dictionary:create
    dictionary:delete
    dictionary:read
    dictionary:refresh
    dictionary:update
    file:read
    file:write
    job:create
    job:delete
    job:read
    job:run
    job:update
    job:update-status
    login-log:delete
    login-log:export
    login-log:read
    menu:create
    menu:delete
    menu:manage
    menu:read
    menu:update
    mfa:manage
    notice:create
    notice:delete
    notice:read
    notice:update
    online-session:read
    online-session:revoke
    operation-log:delete
    operation-log:export
    operation-log:read
    permission:manage
    permission:read
    post:create
    post:delete
    post:export
    post:read
    post:update
    role:assign
    role:create
    role:delete
    role:export
    role:manage
    role:read
    role:update
    server:read
    session:read
    session:revoke
    user:create
    user:delete
    user:export
    user:import
    user:read
    user:reset-password
    user:update
  )

  @doc "返回新系统登记的全部权限。"
  def permissions, do: @permissions

  @doc "检查权限是否已登记在新系统权限目录中。"
  def registered?(permission) when is_binary(permission),
    do: normalize(permission) in @permissions

  def registered?(_permission), do: false

  @doc "返回全部权限的稳定元数据。"
  def entries, do: Enum.map(@permissions, &metadata!/1)

  @doc "去除权限两端空白。"
  def normalize(permission) when is_binary(permission), do: String.trim(permission)
  def normalize(_permission), do: ""

  @doc "检查权限是否符合 resource:action 格式。"
  def valid?(permission) when is_binary(permission),
    do: Regex.match?(@permission_pattern, normalize(permission))

  def valid?(_permission), do: false

  @doc "校验一个权限并返回元数据。"
  def validate(permission) do
    normalized = normalize(permission)

    cond do
      normalized == "" -> {:error, :empty_permission}
      not valid?(normalized) -> {:error, :invalid_permission}
      normalized in @permissions -> {:ok, metadata!(normalized)}
      true -> {:ok, metadata(normalized, false)}
    end
  end

  @doc "检查权限列表中的格式错误和重复项。"
  def validate_catalog(permissions) when is_list(permissions) do
    normalized = Enum.map(permissions, &normalize/1)
    duplicates = normalized -- Enum.uniq(normalized)
    invalid = Enum.reject(normalized, &valid?/1)

    if duplicates == [] and invalid == [],
      do: {:ok, Enum.map(normalized, &metadata(&1, &1 in @permissions))},
      else: {:error, %{duplicates: Enum.uniq(duplicates), invalid: Enum.uniq(invalid)}}
  end

  def validate_catalog(_permissions), do: {:error, %{duplicates: [], invalid: [:not_a_list]}}

  @doc "返回已登记或格式正确的权限元数据。"
  def metadata(permission, registered? \\ nil) do
    normalized = normalize(permission)
    [resource, action] = String.split(normalized, ":", parts: 2)

    %{
      permission: normalized,
      resource: resource,
      # 数据库迁移完成前保留非授权用途的默认分组字段。
      domain: "default",
      action: action,
      description: "#{resource} #{action}",
      risk: risk(action),
      deprecated: false,
      registered?: registered? == true or normalized in @permissions
    }
  end

  defp metadata!(permission), do: metadata(permission, true)

  defp risk(action) when action in ["delete", "revoke", "reset-password", "manage"], do: :high

  defp risk(action)
       when action in ["create", "update", "update-status", "run", "rotate", "import", "export"],
       do: :medium

  defp risk(_action), do: :low
end
