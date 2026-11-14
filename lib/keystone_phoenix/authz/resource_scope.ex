defmodule KeystonePhoenix.Authz.ResourceScope do
  @moduledoc """
  统一资源入口的数据范围规则。

  查询型 `user` 和 `department` 仍由现有列表过滤器处理。本模块只处理入口级资源：
  具有当前用户关系的资源使用 `SELF`、`OWNER`、`MEMBER`，没有稳定关系的管理资源
  只接受 `ALL` 或 `TENANT`。缺少角色、范围或关系时默认拒绝。
  """

  alias KeystonePhoenix.Authz.DataScope
  alias KeystonePhoenix.Authz.Principal
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole

  @tenant_scopes ~w(ALL TENANT)

  @resource_kinds %{
    profile: :self,
    api_key: :self,
    owned: :relationship,
    role: :global,
    post: :global,
    menu: :global,
    config: :global,
    dictionary: :global,
    audit: :global,
    session: :global,
    job: :owner_or_global,
    notice: :owner_or_global,
    file: :global
  }

  @doc "返回已登记的资源入口规则，供文档和测试核对。"
  def rules do
    Enum.into(@resource_kinds, %{}, fn {resource, kind} ->
      {resource, %{kind: kind, scopes: DataScope.scopes_for(resource)}}
    end)
  end

  @doc "检查主体是否可以进入指定资源；缺少目标关系时默认拒绝。"
  def allowed?(principal, resource, context \\ %{})

  def allowed?(principal, resource, context) when is_map(context) do
    subject = Principal.from_user(principal)
    resource_rule = rule(resource)

    cond do
      admin?(subject) -> true
      resource_rule -> allowed_by_rule?(subject, resource_rule, context)
      true -> false
    end
  rescue
    _error -> false
  end

  def allowed?(_principal, _resource, _context), do: false

  @doc "Returns the query scope for resources with an explicit owner relation."
  def owner_scope(principal, resource) do
    subject = Principal.from_user(principal)
    resource_rule = rule(resource)

    cond do
      admin?(subject) ->
        {:ok, :all}

      is_nil(resource_rule) ->
        {:error, :data_scope_denied}

      resource_rule.kind != :owner_or_global ->
        {:error, :data_scope_denied}

      role_scope(subject) in @tenant_scopes ->
        {:ok, :all}

      role_scope(subject) == "OWNER" and canonical_id?(subject.subject_id) ->
        {:ok, {:owner, subject.subject_id}}

      true ->
        {:error, :data_scope_denied}
    end
  rescue
    _error -> {:error, :data_scope_denied}
  end

  @doc "返回资源的规范规则；未知资源返回 nil。"
  def rule(resource) when is_atom(resource) do
    case Map.get(@resource_kinds, resource) do
      nil -> nil
      kind -> %{kind: kind, scopes: DataScope.scopes_for(resource)}
    end
  end

  def rule(resource) when is_binary(resource) do
    resource
    |> String.trim()
    |> String.replace("-", "_")
    |> String.to_existing_atom()
    |> rule()
  rescue
    ArgumentError -> nil
  end

  def rule(_resource), do: nil

  @doc "检查资源是否登记，避免入口使用未定义的资源名称。"
  def registered?(resource), do: not is_nil(rule(resource))

  defp allowed_by_rule?(subject, %{kind: :self}, context) do
    subject_id = subject.subject_id
    target_id = Map.get(context, :target_id, Map.get(context, "target_id", subject_id))

    is_binary(subject_id) and is_binary(target_id) and canonical_id?(subject_id) and
      canonical_id?(target_id) and subject_id == target_id
  end

  defp allowed_by_rule?(subject, %{kind: :relationship}, context) do
    subject_id = subject.subject_id
    owner_id = Map.get(context, :owner_id, Map.get(context, "owner_id"))
    member_ids = Map.get(context, :member_ids, Map.get(context, "member_ids", []))

    is_binary(subject_id) and canonical_id?(subject_id) and
      ((is_binary(owner_id) and owner_id == subject_id) or subject_id in List.wrap(member_ids))
  end

  defp allowed_by_rule?(subject, %{kind: :global, scopes: allowed_scopes}, _context) do
    scope = role_scope(subject)
    scope in allowed_scopes and scope in @tenant_scopes
  end

  defp allowed_by_rule?(subject, %{kind: :owner_or_global}, context) do
    case role_scope(subject) do
      scope when scope in @tenant_scopes ->
        true

      "OWNER" ->
        if Map.get(context, :defer_owner, Map.get(context, "defer_owner", false)) do
          true
        else
          owner_id = Map.get(context, :owner_id, Map.get(context, "owner_id"))
          canonical_id?(subject.subject_id) and owner_id == subject.subject_id
        end

      _scope ->
        false
    end
  end

  defp allowed_by_rule?(_subject, _rule, _context), do: false

  defp admin?(subject), do: Principal.admin?(subject) or Authz.admin?(subject)

  defp role_scope(%Principal{raw: raw, roles: roles}) do
    with nil <- direct_scope(raw),
         role_id when is_binary(role_id) <- role_id(raw, roles),
         {:ok, role_id} <- Params.parse_uuid(role_id),
         %SysRole{data_scope: scope} <- Repo.get_by(SysRole, role_id: role_id, deleted: false) do
      DataScope.normalize(scope)
    else
      scope when is_binary(scope) -> DataScope.normalize(scope)
      _ -> nil
    end
  rescue
    _error -> nil
  end

  defp direct_scope(raw) when is_map(raw) do
    raw
    |> Map.get(:data_scope, Map.get(raw, "data_scope", Map.get(raw, "dataScope")))
    |> normalize_optional_scope()
  end

  defp direct_scope(_raw), do: nil

  defp normalize_optional_scope(scope) when is_binary(scope), do: DataScope.normalize(scope)
  defp normalize_optional_scope(_scope), do: nil

  defp role_id(raw, roles) when is_map(raw) do
    Map.get(raw, :role_id, Map.get(raw, "role_id", Map.get(raw, "roleId"))) || List.first(roles)
  end

  defp role_id(_raw, roles), do: List.first(roles)

  defp canonical_id?(value) do
    case Params.parse_uuid(value) do
      {:ok, ^value} -> true
      _ -> false
    end
  end
end
