defmodule KeystonePhoenix.Authz.DataScope do
  @moduledoc """
  统一数据范围目录和资源适用规则。

  角色字段只保存规范名称。未登记的范围或资源组合必须拒绝，不能因为缺少上下文而扩大访问范围。
  """

  @scopes ~w(ALL TENANT SELF DEPARTMENT DEPARTMENT_AND_CHILDREN CUSTOM OWNER MEMBER)

  @resource_scopes %{
    user: ~w(ALL TENANT SELF DEPARTMENT DEPARTMENT_AND_CHILDREN CUSTOM),
    department: ~w(ALL TENANT DEPARTMENT DEPARTMENT_AND_CHILDREN CUSTOM),
    owned: ~w(ALL OWNER MEMBER)
  }

  @doc "Returns all cross-project data scope names in their canonical order."
  def values, do: @scopes

  @doc "Checks whether a scope name is registered."
  def registered?(scope), do: normalize(scope) in @scopes

  @doc "Checks whether a scope is defined for a resource family."
  def supported?(resource, scope) when is_atom(resource),
    do: normalize(scope) in Map.get(@resource_scopes, resource, [])

  def supported?(_resource, _scope), do: false

  @doc "Normalizes a scope name without accepting unknown values."
  def normalize(scope) when is_binary(scope), do: scope |> String.trim() |> String.upcase()
  def normalize(_scope), do: ""
end
