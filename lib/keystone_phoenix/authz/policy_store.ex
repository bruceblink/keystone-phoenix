defmodule KeystonePhoenix.Authz.PolicyStore do
  @moduledoc """
  Compatibility policy store for the first authorization migration phase.

  The normalized policy tables are intentionally deferred.  This adapter keeps
  the new decision point independent from the current `sys_role`, `sys_menu`
  and `sys_role_menu` backed implementation.
  """

  import Ecto.Query

  alias KeystonePhoenix.Authz.SysPermission
  alias KeystonePhoenix.Permission
  alias KeystonePhoenix.Authz.Principal
  alias KeystonePhoenix.Authz.PolicyCache
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Repo

  @doc "Applies the legacy role data scope to a user or role-user query."
  def scope_query(query, principal), do: Permission.scope_users(query, principal)

  @doc "Checks an exact permission string against the current policy tables."
  def allowed?(principal, permission) do
    case allowed_decision?(principal, permission) do
      :allow -> true
      _ -> false
    end
  end

  @doc "Returns an exact permission decision while preserving storage failures."
  def allowed_decision?(principal, permission) do
    cond do
      admin?(principal) ->
        :allow

      is_list(permission_snapshot(principal)) and is_binary(permission) ->
        if String.trim(permission) in permission_snapshot(principal), do: :allow, else: :deny

      is_list(permission_snapshot(principal)) ->
        :deny

      true ->
        role_id = Map.get(principal, :role_id, Map.get(principal, "roleId"))

        PolicyCache.decision(role_id, String.trim(permission), fn ->
          case normalized_decision(role_id, String.trim(permission)) do
            :miss -> Permission.allowed_decision?(principal, permission)
            decision -> decision
          end
        end)
    end
  end

  @doc "Checks a single target against a role data scope."
  def scope_allowed?(principal, :dept, target),
    do: Permission.data_scope_allowed?(principal, :dept, target)

  def scope_allowed?(principal, :user, target),
    do: Permission.data_scope_allowed?(principal, :user, target)

  def scope_allowed?(principal, :users, target),
    do: Permission.data_scope_users_allowed?(principal, target)

  def scope_allowed?(principal, :user_update, {target_id, attrs}),
    do: Permission.user_update_allowed?(principal, target_id, attrs)

  def scope_allowed?(principal, :user_update, target),
    do: Permission.user_update_allowed?(principal, target, %{})

  def scope_allowed?(principal, :self, target) do
    subject = Principal.from_user(principal)

    if Principal.admin?(subject) do
      true
    else
      with {:ok, subject_id} <- Params.parse_positive_integer(subject.subject_id),
           {:ok, target_id} <- Params.parse_positive_integer(target) do
        subject_id == target_id
      else
        _ -> false
      end
    end
  end

  def scope_allowed?(_principal, :none, _target), do: true
  def scope_allowed?(_principal, _kind, _target), do: false

  @doc "Checks whether a role write may change permission metadata."
  def role_metadata_allowed?(principal, attrs),
    do: Permission.role_metadata_allowed?(principal, attrs)

  @doc "Checks whether a menu write may change permission metadata."
  def menu_metadata_allowed?(principal, attrs),
    do: Permission.menu_metadata_allowed?(principal, attrs)

  @doc "Checks whether an actor may assign the requested role."
  def role_assignment_allowed?(principal, role_id),
    do: Permission.role_assignment_allowed?(principal, role_id)

  defp admin?(%{is_admin: true}), do: true
  defp admin?(%{"isAdmin" => value}), do: value in [true, 1, "1"]
  defp admin?(_principal), do: false

  defp permission_snapshot(principal) when is_map(principal),
    do: Map.get(principal, :permissions, Map.get(principal, "permissions"))

  defp permission_snapshot(_principal), do: nil

  defp normalized_decision(role_id, permission) do
    with {:ok, role_id} <- Params.parse_positive_integer(role_id),
         true <- is_binary(permission) and permission != "",
         permission_id when is_integer(permission_id) <- permission_id(permission) do
      if Repo.exists?(
           from role_permission in "sys_role_permission",
             join: role in "sys_role",
             on: role.role_id == role_permission.role_id,
             where:
               role_permission.role_id == ^role_id and
                 role_permission.permission_id == ^permission_id and
                 role.deleted == false and role.status == 1
         ),
         do: :allow,
         else: :deny
    else
      :miss -> :miss
      false -> :miss
      :error -> :miss
      _ -> :miss
    end
  rescue
    _error -> {:error, :authorization_unavailable}
  end

  defp permission_id(permission) do
    Repo.one(
      from entry in SysPermission,
        where:
          entry.permission == ^permission and entry.status == 1 and entry.deprecated == false,
        select: entry.permission_id
    ) || :miss
  end
end
