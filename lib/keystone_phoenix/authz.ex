defmodule KeystonePhoenix.Authz do
  @moduledoc """
  Unified authorization decision point.

  Permission checks and data-scope checks are kept separate so HTTP, LiveView
  and domain callers can compose the same decision.  The first implementation
  delegates policy reads to `Authz.PolicyStore`, which adapts the existing RBAC
  tables without changing their schema.
  """

  import Ecto.Query, only: [where: 2]

  alias KeystonePhoenix.Authz.PolicyStore
  alias KeystonePhoenix.Authz.Principal

  @type denial ::
          {:error, :permission_denied}
          | {:error, :data_scope_denied}
          | {:error, :authorization_unavailable}

  @doc "Returns true when a subject has an exact permission string."
  @spec allowed?(map() | Principal.t(), String.t(), map()) :: boolean()
  def allowed?(principal, permission, context \\ %{})

  def allowed?(principal, permission, _context) when is_binary(permission) do
    subject = Principal.from_user(principal)

    cond do
      Principal.admin?(subject) -> true
      permission == "" -> false
      is_list(subject.permissions) -> permission in subject.permissions
      true -> PolicyStore.allowed?(Principal.to_user(subject), permission)
    end
  rescue
    _error -> false
  end

  def allowed?(_principal, _permission, _context), do: false

  @doc "Returns whether an actor has administrator status."
  def admin?(principal), do: Principal.admin?(Principal.from_user(principal))

  @doc "Applies the actor's data scope to an Ecto query."
  def scope_query(query, principal) do
    subject = principal |> Principal.from_user() |> Principal.to_user()
    PolicyStore.scope_query(query, subject)
  rescue
    _error -> where(query, false)
  end

  @doc "Checks whether a role write may change permission metadata."
  def role_metadata_allowed?(principal, attrs) when is_map(attrs) do
    PolicyStore.role_metadata_allowed?(Principal.to_user(Principal.from_user(principal)), attrs)
  rescue
    _error -> false
  end

  def role_metadata_allowed?(_principal, _attrs), do: false

  @doc "Checks whether a menu write may change permission metadata."
  def menu_metadata_allowed?(principal, attrs) when is_map(attrs) do
    PolicyStore.menu_metadata_allowed?(Principal.to_user(Principal.from_user(principal)), attrs)
  rescue
    _error -> false
  end

  def menu_metadata_allowed?(_principal, _attrs), do: false

  @doc "Checks whether an actor may assign the requested role."
  def role_assignment_allowed?(principal, role_id) do
    PolicyStore.role_assignment_allowed?(
      Principal.to_user(Principal.from_user(principal)),
      role_id
    )
  rescue
    _error -> false
  end

  @doc """
  Checks a permission and, when present, the requested target scope.

  `resource` is passed through as the default target.  A scope can be supplied
  in `context` as `:scope`/`"scope"`, using the same tuples as the HTTP Plug:
  `{:dept, key}`, `{:user, key}`, `{:user_update, key}` or `{:users, key}`.
  """
  @spec authorize(map() | Principal.t(), String.t(), term(), map()) :: :ok | denial()
  def authorize(principal, permission, resource \\ nil, context \\ %{}) do
    if allowed?(principal, permission, context) do
      case scope_decision(principal, resource, context) do
        true -> :ok
        false -> {:error, :data_scope_denied}
      end
    else
      {:error, :permission_denied}
    end
  rescue
    _error -> {:error, :authorization_unavailable}
  end

  @doc "Returns true when a subject may access a target in its data scope."
  @spec scope_allowed?(map() | Principal.t(), atom(), term(), map()) :: boolean()
  def scope_allowed?(principal, kind, target, context \\ %{}) do
    subject = Principal.to_user(Principal.from_user(principal))
    target = scope_target(kind, target, context)
    PolicyStore.scope_allowed?(subject, kind, target)
  rescue
    _error -> false
  end

  defp scope_decision(principal, resource, context) when is_map(context) do
    case context_value(context, :scope, nil) do
      nil ->
        true

      :none ->
        true

      {:dept, key} ->
        scope_allowed?(principal, :dept, context_target(context, key, resource), context)

      {:user, key} ->
        scope_allowed?(principal, :user, context_target(context, key, resource), context)

      {:users, key} ->
        scope_allowed?(principal, :users, context_target(context, key, resource), context)

      {:user_update, key} ->
        attrs = context_value(context, :attrs, %{})

        scope_allowed?(
          principal,
          :user_update,
          context_target(context, key, resource),
          Map.put(context, :attrs, attrs)
        )

      kind when kind in [:dept, :user, :users, :user_update] ->
        scope_allowed?(principal, kind, resource, context)

      _scope ->
        false
    end
  end

  defp scope_decision(_principal, _resource, _context), do: false

  defp scope_target(:user_update, target, context),
    do: {target, context_value(context, :attrs, %{})}

  defp scope_target(_kind, target, _context), do: target

  defp context_target(context, key, resource) do
    case context_value(context, :params, nil) do
      params when is_map(params) ->
        Map.get(params, key, Map.get(params, to_string(key), resource))

      _ ->
        context_value(context, key, resource)
    end
  end

  defp context_value(context, atom_key, default) do
    string_key = to_string(atom_key)
    Map.get(context, atom_key, Map.get(context, string_key, default))
  end
end
