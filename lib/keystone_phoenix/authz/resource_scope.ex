defmodule KeystonePhoenix.Authz.ResourceScope do
  @moduledoc """
  统一资源入口的数据范围规则。

  查询型 `user` 和 `department` 仍由现有列表过滤器处理。本模块只处理入口级资源：
  具有当前用户关系的资源使用 `SELF`、`OWNER`、`MEMBER`，没有稳定关系的管理资源
  只接受 `ALL` 或 `TENANT`。缺少角色、范围或关系时默认拒绝。
  """

  alias KeystonePhoenix.Authz.DataScope
  alias KeystonePhoenix.Authz.Principal
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Permission

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
      is_nil(resource_rule) ->
        {:error, :data_scope_denied}

      resource_rule.kind != :owner_or_global ->
        {:error, :data_scope_denied}

      true ->
        scopes = role_scopes(subject)

        cond do
          Enum.any?(scopes, &(&1 in @tenant_scopes)) ->
            {:ok, :all}

          "OWNER" in scopes and canonical_id?(Principal.scope_subject_id(subject)) ->
            {:ok, {:owner, Principal.scope_subject_id(subject)}}

          true ->
            {:error, :data_scope_denied}
        end
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
    subject_id = Principal.scope_subject_id(subject)
    target_id = Map.get(context, :target_id, Map.get(context, "target_id", subject_id))

    is_binary(subject_id) and is_binary(target_id) and canonical_id?(subject_id) and
      canonical_id?(target_id) and subject_id == target_id
  end

  defp allowed_by_rule?(subject, %{kind: :relationship}, context) do
    subject_id = Principal.scope_subject_id(subject)
    owner_id = Map.get(context, :owner_id, Map.get(context, "owner_id"))
    member_ids = Map.get(context, :member_ids, Map.get(context, "member_ids", []))

    is_binary(subject_id) and canonical_id?(subject_id) and
      ((is_binary(owner_id) and owner_id == subject_id) or subject_id in List.wrap(member_ids))
  end

  defp allowed_by_rule?(subject, %{kind: :global, scopes: allowed_scopes}, _context) do
    Enum.any?(role_scopes(subject), &(&1 in allowed_scopes and &1 in @tenant_scopes))
  end

  defp allowed_by_rule?(subject, %{kind: :owner_or_global}, context) do
    scopes = role_scopes(subject)

    cond do
      Enum.any?(scopes, &(&1 in @tenant_scopes)) ->
        true

      "OWNER" in scopes ->
        if Map.get(context, :defer_owner, Map.get(context, "defer_owner", false)) do
          true
        else
          owner_id = Map.get(context, :owner_id, Map.get(context, "owner_id"))
          scope_subject_id = Principal.scope_subject_id(subject)
          canonical_id?(scope_subject_id) and owner_id == scope_subject_id
        end

      true ->
        false
    end
  end

  defp allowed_by_rule?(_subject, _rule, _context), do: false

  # 入口数据范围必须与用户查询使用相同的启用角色并集规则。
  defp role_scopes(%Principal{raw: raw} = subject) do
    case direct_scope(raw) do
      nil -> Permission.active_data_scopes(subject)
      scope -> [scope]
    end
  end

  defp direct_scope(raw) when is_map(raw) do
    raw
    |> Map.get(:data_scope, Map.get(raw, "data_scope", Map.get(raw, "dataScope")))
    |> normalize_optional_scope()
  end

  defp direct_scope(_raw), do: nil

  defp normalize_optional_scope(scope) when is_binary(scope), do: DataScope.normalize(scope)
  defp normalize_optional_scope(_scope), do: nil

  defp canonical_id?(value) do
    case Params.parse_uuid(value) do
      {:ok, ^value} -> true
      _ -> false
    end
  end
end
