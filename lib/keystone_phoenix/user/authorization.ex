defmodule KeystonePhoenix.User.Authorization do
  @moduledoc "Authorization checks for principal-aware user write commands."

  alias KeystonePhoenix.Authz

  def authorize_create(attrs, options) do
    with {:ok, principal, permission} <- authorization_options(options, "system:user:add"),
         :ok <- authorize_permission(principal, permission),
         :ok <- authorize_scope(principal, :dept, attr_value(attrs, "deptId", :dept_id)),
         true <- Authz.role_assignment_allowed?(principal, attr_value(attrs, "roleId", :role_id)) do
      :ok
    else
      false -> {:error, :role_assignment_forbidden}
      error -> error
    end
  end

  def authorize_update(id, attrs, options) do
    with {:ok, principal, permission} <- authorization_options(options, "system:user:edit"),
         :ok <- authorize_permission(principal, permission),
         :ok <- authorize_scope(principal, :user_update, id, %{attrs: attrs}),
         true <- Authz.role_assignment_allowed?(principal, attr_value(attrs, "roleId", :role_id)) do
      :ok
    else
      false -> {:error, :role_assignment_forbidden}
      error -> error
    end
  end

  def authorize_delete(ids, options) do
    with {:ok, principal, permission} <- authorization_options(options, "system:user:remove"),
         :ok <- authorize_permission(principal, permission),
         :ok <- authorize_scope(principal, :users, ids) do
      :ok
    end
  end

  def authorize_target(id, options, default_permission) do
    with {:ok, principal, permission} <- authorization_options(options, default_permission),
         :ok <- authorize_permission(principal, permission),
         :ok <- authorize_scope(principal, :user, id) do
      :ok
    end
  end

  def actor_id(options) do
    authorization = Keyword.fetch!(options, :authorization)
    actor_id = Map.get(authorization, :actor_id, Map.get(authorization, "actor_id"))

    actor_id ||
      authorization
      |> Map.get(:principal, Map.get(authorization, "principal"))
      |> Authz.Principal.from_user()
      |> Map.get(:subject_id)
  end

  defp authorization_options(options, default_permission) do
    case Keyword.get(options, :authorization) do
      authorization when is_map(authorization) ->
        principal = Map.get(authorization, :principal, Map.get(authorization, "principal"))
        permission = Map.get(authorization, :permission, default_permission)

        if is_map(principal) and is_binary(permission),
          do: {:ok, principal, permission},
          else: {:error, :authorization_required}

      _ ->
        {:error, :authorization_required}
    end
  end

  defp authorize_permission(principal, permission) do
    if Authz.allowed?(principal, permission), do: :ok, else: {:error, :permission_denied}
  end

  defp authorize_scope(principal, kind, target, context \\ %{}) do
    if Authz.scope_allowed?(principal, kind, target, context),
      do: :ok,
      else: {:error, :data_scope_denied}
  end

  defp attr_value(attrs, string_key, atom_key),
    do: Map.get(attrs, string_key, Map.get(attrs, atom_key))
end
