defmodule KeystonePhoenix.Authz.DataScope do
  @moduledoc """
  统一数据范围目录和资源适用规则。

  角色字段只保存规范名称。未登记的范围或资源组合必须拒绝，不能因为缺少上下文而扩大访问范围。
  """

  @scopes ~w(ALL TENANT SELF DEPARTMENT DEPARTMENT_AND_CHILDREN CUSTOM OWNER MEMBER)

  @resource_scopes %{
    user: ~w(ALL TENANT SELF DEPARTMENT DEPARTMENT_AND_CHILDREN CUSTOM),
    department: ~w(ALL TENANT DEPARTMENT DEPARTMENT_AND_CHILDREN CUSTOM),
    profile: ~w(SELF),
    api_key: ~w(SELF),
    owned: ~w(OWNER MEMBER),
    role: ~w(ALL TENANT),
    post: ~w(ALL TENANT),
    menu: ~w(ALL TENANT),
    config: ~w(ALL TENANT),
    dictionary: ~w(ALL TENANT),
    audit: ~w(ALL TENANT),
    session: ~w(ALL TENANT),
    job: ~w(ALL TENANT OWNER),
    notice: ~w(ALL TENANT OWNER),
    file: ~w(ALL TENANT)
  }

  @doc "Returns all cross-project data scope names in their canonical order."
  def values, do: @scopes

  @doc "Checks whether a scope name is registered."
  def registered?(scope), do: normalize(scope) in @scopes

  @doc "Returns the registered scopes for a resource family."
  def scopes_for(resource) when is_atom(resource), do: Map.get(@resource_scopes, resource, [])

  def scopes_for(resource) when is_binary(resource) do
    resource
    |> String.trim()
    |> String.replace("-", "_")
    |> String.to_existing_atom()
    |> scopes_for()
  rescue
    ArgumentError -> []
  end

  def scopes_for(_resource), do: []

  @doc "Checks whether a scope is defined for a resource family."
  def supported?(resource, scope), do: normalize(scope) in scopes_for(resource)

  @doc "Returns all registered resource families."
  def resources, do: Map.keys(@resource_scopes)

  @doc "Normalizes a scope name without accepting unknown values."
  def normalize(scope) when is_binary(scope), do: scope |> String.trim() |> String.upcase()
  def normalize(_scope), do: ""
end
