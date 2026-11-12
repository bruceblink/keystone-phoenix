defmodule KeystonePhoenix.User do
  @moduledoc """
  Query boundary for system users.

  Passwords are hashed at write time and are never included in API maps.
  """

  import Ecto.Query

  alias KeystonePhoenix.Audit
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Auth.Session
  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Post
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Pagination
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.User.Authorization
  alias KeystonePhoenix.User.SysUser

  @empty_relation_names %{departments: %{}, posts: %{}, roles: %{}, users: %{}}

  @user_attrs [
    {"postId", :post_id},
    {"roleId", :role_id},
    {"deptId", :dept_id},
    {"username", :username},
    {"nickname", :nickname},
    {"email", :email},
    {"phoneNumber", :phone_number},
    {"sex", :sex},
    {"avatar", :avatar},
    {"status", :status},
    {"remark", :remark},
    {"password", :password}
  ]

  @spec list_users(map()) :: %{rows: list(), total: non_neg_integer()}
  def list_users(params \\ %{}) do
    params |> users_query() |> page_query(params)
  end

  @doc "Lists only users in the authenticated actor's data scope."
  @spec list_users(map(), map()) :: %{rows: list(), total: non_neg_integer()}
  def list_users(params, actor) do
    params |> users_query() |> Authz.scope_query(actor) |> page_query(params)
  end

  defp users_query(params) do
    query =
      from u in SysUser,
        where: u.deleted == false,
        order_by: [desc: u.user_id]

    query
    |> filter_integer(:user_id, params["userId"] || params[:user_id])
    |> filter_contains(:username, params["username"] || params[:username])
    |> filter_contains(:phone_number, params["phoneNumber"] || params[:phone_number])
    |> filter_integer(:status, params["status"] || params[:status])
    |> filter_integer(:dept_id, params["deptId"] || params[:dept_id])
  end

  @spec get_user(integer() | String.t()) :: {:ok, SysUser.t()} | {:error, :not_found}
  def get_user(id) do
    case Params.parse_positive_integer(id) do
      {:ok, id} ->
        case Repo.get_by(SysUser, user_id: id, deleted: false) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc "Returns active users keyed by ID with one database query."
  @spec list_users_by_ids(list()) :: [SysUser.t()]
  def list_users_by_ids(ids) when is_list(ids) do
    ids = ids |> Enum.map(&parse_positive_integer/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      []
    else
      from(u in SysUser, where: u.deleted == false and u.user_id in ^ids)
      |> Repo.all()
    end
  end

  def list_users_by_ids(_ids), do: []

  @spec get_user_by_username(String.t()) :: {:ok, SysUser.t()} | {:error, :not_found}
  def get_user_by_username(username) when is_binary(username) do
    case Repo.get_by(SysUser, username: username, deleted: false) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def get_user_by_username(_username), do: {:error, :not_found}

  @doc "Creates a local user and stores only a bcrypt password hash."
  @spec create_user(map(), keyword()) :: {:ok, SysUser.t()} | {:error, term()}
  def create_user(attrs, options)

  def create_user(attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Authorization.authorize_create(attrs, options) do
      do_create_user(attrs, Authorization.actor_id(options))
    end
  end

  def create_user(_attrs, _options), do: {:error, :authorization_required}

  defp do_create_user(attrs, actor_id) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with :ok <- validate_relations(attrs) do
      %SysUser{}
      |> SysUser.create_changeset(attrs)
      |> Audit.put_actor(:creator_id, actor_id)
      |> Repo.insert()
    end
  end

  @doc "Updates editable user fields and revokes a disabled user's session."
  @spec update_user(integer() | String.t(), map(), keyword()) ::
          {:ok, SysUser.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_user(id, attrs, options)

  def update_user(id, attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Authorization.authorize_update(id, attrs, options) do
      do_update_user(id, attrs, Authorization.actor_id(options))
    end
  end

  def update_user(_id, _attrs, _options), do: {:error, :authorization_required}

  defp do_update_user(id, attrs, actor_id) when is_map(attrs) do
    with {:ok, user} <- get_user(id) do
      attrs = normalize_attrs(attrs)

      case validate_relations(attrs) do
        :ok -> update_user_record(user, attrs, actor_id)
        error -> error
      end
    end
  end

  defp update_user_record(user, attrs, actor_id) do
    changeset = SysUser.update_changeset(user, attrs) |> Audit.put_actor(:updater_id, actor_id)

    case Repo.update(changeset) do
      {:ok, updated} = result ->
        revoke_if_disabled(user, updated)
        result

      error ->
        error
    end
  end

  @doc "Soft deletes users and prevents deleting the current or an administrator account."
  @spec delete_users(list(), keyword()) :: :ok | {:error, atom()}
  def delete_users(ids, options) when is_list(ids) and is_list(options) do
    with :ok <- Authorization.authorize_delete(ids, options) do
      do_delete_users(ids, Authorization.actor_id(options))
    end
  end

  def delete_users(_ids, _options), do: {:error, :authorization_required}

  defp do_delete_users(ids, actor_id) when is_list(ids) do
    ids = ids |> Enum.map(&parse_positive_integer/1) |> Enum.uniq()
    actor_id = parse_positive_integer(actor_id)

    if Enum.any?(ids, &is_nil/1) or is_nil(actor_id) or ids == [] do
      {:error, :invalid_ids}
    else
      case Repo.transaction(fn -> delete_users_in_transaction(ids, actor_id) end) do
        {:ok, :ok} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "Replaces a user's password and invalidates the active refresh session."
  @spec reset_password(integer() | String.t(), map(), keyword()) ::
          {:ok, SysUser.t()} | {:error, :not_found | :unavailable | Ecto.Changeset.t()}
  def reset_password(id, attrs, options)

  def reset_password(id, attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Authorization.authorize_target(id, options, "system:user:resetPwd") do
      do_reset_password(id, attrs, Authorization.actor_id(options))
    end
  end

  def reset_password(_id, _attrs, _options), do: {:error, :authorization_required}

  defp do_reset_password(id, attrs, actor_id) when is_map(attrs) do
    with {:ok, user_id} <- Params.parse_positive_integer(id) do
      Session.update_account_and_revoke(user_id, fn ->
        with {:ok, user} <- get_user(user_id) do
          user
          |> SysUser.password_changeset(normalize_attrs(attrs))
          |> Audit.put_actor(:updater_id, actor_id)
          |> Repo.update()
        end
      end)
    else
      :error -> {:error, :not_found}
    end
  end

  @doc "Changes a user's enabled status and invalidates disabled sessions."
  @spec change_status(integer() | String.t(), term(), keyword()) ::
          {:ok, SysUser.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def change_status(id, status, options)

  def change_status(id, status, options) when is_list(options) do
    update_user(id, %{"status" => status}, options)
  end

  def change_status(_id, _status, _options), do: {:error, :authorization_required}

  @doc "Returns the profile view for an authenticated user."
  def profile(id) do
    case get_user(id) do
      {:ok, user} ->
        user = user_to_map_with_relations(user)

        {:ok,
         %{
           "user" => user,
           "roleName" => user["roleName"] || "",
           "postName" => user["postName"] || ""
         }}

      error ->
        error
    end
  end

  @doc "Maps users with the department, role, post, and audit actor names used by the frontend."
  def user_maps(users) when is_list(users) do
    names = relation_names(users)
    Enum.map(users, &user_to_map(&1, names))
  end

  def user_maps(_users), do: []

  @doc "Maps one user with the related display names required by profile and login responses."
  def user_to_map_with_relations(user),
    do: user |> List.wrap() |> user_maps() |> List.first() || user_to_map(user)

  @doc "Updates editable profile fields without allowing account privilege changes."
  @spec update_profile(integer() | String.t(), map(), keyword()) ::
          {:ok, SysUser.t()} | {:error, term()}
  def update_profile(id, attrs, options)

  def update_profile(id, attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Authorization.authorize_self(id, options) do
      do_update_profile(id, attrs, Authorization.actor_id(options))
    end
  end

  def update_profile(_id, _attrs, _options), do: {:error, :authorization_required}

  defp do_update_profile(id, attrs, actor_id) when is_map(attrs) do
    attrs =
      %{}
      |> maybe_put(attrs, "nickname", ["nickName", "nickname"])
      |> maybe_put(attrs, "phoneNumber", ["phoneNumber", "phone_number"])
      |> maybe_put(attrs, "email", ["email"])
      |> maybe_put(attrs, "sex", ["sex"])

    do_update_user(id, attrs, actor_id)
  end

  @doc "Changes a password after checking the current password."
  @spec update_password(integer() | String.t(), map(), keyword()) ::
          {:ok, SysUser.t()} | {:error, term()}
  def update_password(id, attrs, options)

  def update_password(id, attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Authorization.authorize_self(id, options) do
      do_update_password(id, attrs, Authorization.actor_id(options))
    end
  end

  def update_password(_id, _attrs, _options), do: {:error, :authorization_required}

  defp do_update_password(id, attrs, actor_id) when is_map(attrs) do
    with {:ok, user_id} <- Params.parse_positive_integer(id),
         {:ok, old_password, new_password} <- password_inputs(attrs) do
      Session.update_account_and_revoke(user_id, fn ->
        with {:ok, user} <- get_user(user_id),
             true <- Bcrypt.verify_pass(old_password, user.password || ""),
             false <- Bcrypt.verify_pass(new_password, user.password || "") do
          SysUser.password_changeset(user, %{password: new_password})
          |> Audit.put_actor(:updater_id, actor_id)
          |> Repo.update()
        else
          {:error, :not_found} -> {:error, :not_found}
          false -> {:error, :invalid_old_password}
          true -> {:error, :same_password}
        end
      end)
    else
      {:error, :invalid_password_input} -> {:error, invalid_changeset(%SysUser{}, :password)}
      :error -> {:error, :not_found}
    end
  end

  @doc "Updates an avatar URL supplied by the file service."
  @spec update_avatar(integer() | String.t(), String.t(), keyword()) ::
          {:ok, SysUser.t()} | {:error, term()}
  def update_avatar(id, avatar, options)

  def update_avatar(id, avatar, options) when is_list(options) do
    with :ok <- Authorization.authorize_self(id, options) do
      do_update_avatar(id, avatar, Authorization.actor_id(options))
    end
  end

  def update_avatar(_id, _avatar, _options), do: {:error, :authorization_required}

  defp do_update_avatar(id, avatar, actor_id) when is_binary(avatar) do
    do_update_user(id, %{"avatar" => avatar}, actor_id)
  end

  defp maybe_put(target, source, target_key, source_keys) do
    case Enum.find(source_keys, &Map.has_key?(source, &1)) do
      nil -> target
      source_key -> Map.put(target, target_key, Map.get(source, source_key))
    end
  end

  defp validate_relations(attrs) do
    with :ok <- validate_relation(attrs[:dept_id], &Department.get_dept/1, :dept_not_found),
         :ok <- validate_relation(attrs[:post_id], &Post.get_post/1, :post_not_found),
         :ok <- validate_relation(attrs[:role_id], &Role.get_role/1, :role_not_found) do
      :ok
    end
  end

  defp validate_relation(nil, _lookup, _error), do: :ok

  defp validate_relation(id, lookup, error) do
    case lookup.(id) do
      {:ok, _record} -> :ok
      {:error, :not_found} -> {:error, error}
    end
  end

  defp password_inputs(attrs) do
    old_password = attrs["oldPassword"] || attrs[:old_password]
    new_password = attrs["newPassword"] || attrs[:new_password]

    if is_binary(old_password) and is_binary(new_password) do
      {:ok, old_password, new_password}
    else
      {:error, :invalid_password_input}
    end
  end

  @spec user_to_map(SysUser.t()) :: map()
  def user_to_map(user) do
    user_to_map(user, @empty_relation_names)
  end

  defp user_to_map(user, names) do
    %{
      "userId" => user.user_id,
      "postId" => user.post_id,
      "roleId" => user.role_id,
      "deptId" => user.dept_id,
      "username" => user.username,
      "nickname" => user.nickname,
      "userType" => user.user_type,
      "email" => user.email,
      "phoneNumber" => user.phone_number,
      "sex" => user.sex,
      "avatar" => user.avatar,
      "status" => user.status,
      "loginIp" => user.login_ip,
      "loginDate" => format_datetime(user.login_date),
      "isAdmin" => if(user.is_admin, do: 1, else: 0),
      "deptName" => Map.get(names.departments, user.dept_id, ""),
      "postName" => Map.get(names.posts, user.post_id, ""),
      "roleName" => Map.get(names.roles, user.role_id, ""),
      "creatorName" => Map.get(names.users, user.creator_id, ""),
      "updaterName" => Map.get(names.users, user.updater_id, ""),
      "creatorId" => user.creator_id,
      "createTime" => format_datetime(user.create_time),
      "updaterId" => user.updater_id,
      "updateTime" => format_datetime(user.update_time),
      "remark" => user.remark
    }
  end

  defp delete_users_in_transaction(ids, actor_id) do
    Enum.reduce_while(ids, :ok, fn user_id, :ok ->
      case get_user(user_id) do
        {:error, :not_found} ->
          Repo.rollback(:not_found)

        {:ok, user} ->
          if user.user_id == actor_id or user.is_admin do
            Repo.rollback(:protected_user)
          else
            changeset = Ecto.Changeset.change(user, deleted: true)
            changeset = Audit.put_actor(changeset, :updater_id, actor_id)

            case Repo.update(changeset) do
              {:ok, _deleted} ->
                Session.revoke_account(user.user_id)
                {:cont, :ok}

              {:error, _changeset} ->
                Repo.rollback(:update_failed)
            end
          end
      end
    end)
  end

  defp revoke_if_disabled(%{status: 1}, %{status: status, user_id: user_id}) when status != 1 do
    Session.revoke_account(user_id)
  end

  defp revoke_if_disabled(_old_user, _updated_user), do: :ok

  defp normalize_attrs(attrs) when is_map(attrs) do
    Enum.reduce(@user_attrs, %{}, fn {json_key, atom_key}, normalized ->
      cond do
        Map.has_key?(attrs, json_key) ->
          Map.put(
            normalized,
            atom_key,
            normalize_relation_value(atom_key, Map.get(attrs, json_key))
          )

        Map.has_key?(attrs, atom_key) ->
          Map.put(
            normalized,
            atom_key,
            normalize_relation_value(atom_key, Map.get(attrs, atom_key))
          )

        true ->
          normalized
      end
    end)
  end

  defp normalize_relation_value(field, value) when field in [:dept_id, :post_id, :role_id] do
    case value do
      value when is_binary(value) ->
        case Params.parse_integer(value) do
          {:ok, id} when id > 0 -> id
          {:ok, 0} -> nil
          {:ok, _id} -> value
          :error -> if String.trim(value) == "", do: nil, else: value
        end

      value ->
        value
    end
  end

  defp normalize_relation_value(_field, value), do: value

  defp parse_positive_integer(value) do
    case Params.parse_positive_integer(value) do
      {:ok, integer} -> integer
      :error -> nil
    end
  end

  defp invalid_changeset(schema, field) do
    Ecto.Changeset.add_error(Ecto.Changeset.change(schema), field, "参数无效")
  end

  defp page_query(query, params) do
    paged = Pagination.page_rows(query, params, :user_id)
    %{paged | rows: user_maps(paged.rows)}
  end

  defp relation_names(users) do
    %{
      departments:
        users
        |> relation_ids(:dept_id)
        |> Department.list_depts_by_ids()
        |> names_by_id(:dept_id, :dept_name),
      posts:
        users
        |> relation_ids(:post_id)
        |> Post.list_posts_by_ids()
        |> names_by_id(:post_id, :post_name),
      roles:
        users
        |> relation_ids(:role_id)
        |> Role.list_roles_by_ids()
        |> names_by_id(:role_id, :role_name),
      users:
        (relation_ids(users, :creator_id) ++ relation_ids(users, :updater_id))
        |> Enum.uniq()
        |> list_users_by_ids()
        |> names_by_id(:user_id, :username)
    }
  end

  defp relation_ids(users, field) do
    users
    |> Enum.map(&Map.get(&1, field))
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
    |> Enum.uniq()
  end

  defp names_by_id(records, id_field, name_field),
    do: Map.new(records, &{Map.get(&1, id_field), Map.get(&1, name_field)})

  defp filter_integer(query, _field, nil), do: query
  defp filter_integer(query, _field, ""), do: query

  defp filter_integer(query, field, value) do
    value = to_string(value)

    if value == String.trim(value) do
      case Params.parse_integer(value) do
        {:ok, integer} -> where(query, [record], field(record, ^field) == ^integer)
        _ -> query
      end
    else
      query
    end
  end

  defp filter_contains(query, _field, nil), do: query
  defp filter_contains(query, _field, ""), do: query

  defp filter_contains(query, field, value) do
    value = "%#{String.trim(to_string(value))}%"
    where(query, [record], ilike(field(record, ^field), ^value))
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
