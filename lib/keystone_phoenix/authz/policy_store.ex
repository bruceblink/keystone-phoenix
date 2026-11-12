defmodule KeystonePhoenix.Authz.PolicyStore do
  @moduledoc """
  Compatibility policy store for the first authorization migration phase.

  The normalized policy tables are intentionally deferred.  This adapter keeps
  the new decision point independent from the current `sys_role`, `sys_menu`
  and `sys_role_menu` backed implementation.
  """

  alias KeystonePhoenix.Permission

  @doc "Checks an exact permission string against the current policy tables."
  def allowed?(principal, permission) do
    Permission.allowed?(principal, permission)
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
end
