defmodule KeystonePhoenix.User do
  @moduledoc """
  Query boundary for system users.

  Passwords are hashed at write time and are never included in API maps.
  """

  import Ecto.Query

  alias KeystonePhoenix.Auth.Session
  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Post
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.User.SysUser

  @default_page 1
  @default_page_size 10
  @max_page_size 500

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
    query =
      from u in SysUser,
        where: u.deleted == false,
        order_by: [desc: u.user_id]

    query =
      query
      |> filter_integer(:user_id, params["userId"] || params[:user_id])
      |> filter_contains(:username, params["username"] || params[:username])
      |> filter_contains(:phone_number, params["phoneNumber"] || params[:phone_number])
      |> filter_integer(:status, params["status"] || params[:status])
      |> filter_integer(:dept_id, params["deptId"] || params[:dept_id])

    page_query(query, params)
  end

  @spec get_user(integer() | String.t()) :: {:ok, SysUser.t()} | {:error, :not_found}
  def get_user(id) do
    case Repo.get_by(SysUser, user_id: id, deleted: false) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @spec get_user_by_username(String.t()) :: {:ok, SysUser.t()} | {:error, :not_found}
  def get_user_by_username(username) when is_binary(username) do
    case Repo.get_by(SysUser, username: username, deleted: false) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def get_user_by_username(_username), do: {:error, :not_found}

  @doc "Creates a local user and stores only a bcrypt password hash."
  @spec create_user(map()) :: {:ok, SysUser.t()} | {:error, Ecto.Changeset.t()}
  def create_user(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with :ok <- validate_relations(attrs) do
      %SysUser{}
      |> SysUser.create_changeset(attrs)
      |> Repo.insert()
    end
  end

  def create_user(_attrs), do: {:error, invalid_changeset(%SysUser{}, :username)}

  @doc "Updates editable user fields and revokes a disabled user's session."
  @spec update_user(integer() | String.t(), map()) ::
          {:ok, SysUser.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_user(id, attrs) when is_map(attrs) do
    with {:ok, user} <- get_user(id) do
      attrs = normalize_attrs(attrs)

      case validate_relations(attrs) do
        :ok -> update_user_record(user, attrs)
        error -> error
      end
    end
  end

  def update_user(_id, _attrs), do: {:error, invalid_changeset(%SysUser{}, :username)}

  defp update_user_record(user, attrs) do
    case user |> SysUser.update_changeset(attrs) |> Repo.update() do
      {:ok, updated} = result ->
        revoke_if_disabled(user, updated)
        result

      error ->
        error
    end
  end

  @doc "Soft deletes users and prevents deleting the current or an administrator account."
  @spec delete_users(list(), integer() | String.t()) :: :ok | {:error, atom()}
  def delete_users(ids, actor_id) when is_list(ids) do
    ids = Enum.map(ids, &parse_positive_integer/1)
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

  def delete_users(_ids, _actor_id), do: {:error, :invalid_ids}

  @doc "Replaces a user's password and invalidates the active refresh session."
  @spec reset_password(integer() | String.t(), map()) ::
          {:ok, SysUser.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def reset_password(id, attrs) when is_map(attrs) do
    with {:ok, user} <- get_user(id) do
      case user |> SysUser.password_changeset(normalize_attrs(attrs)) |> Repo.update() do
        {:ok, updated} = result ->
          Session.revoke_account(updated.user_id)
          result

        error ->
          error
      end
    end
  end

  def reset_password(_id, _attrs), do: {:error, invalid_changeset(%SysUser{}, :password)}

  @doc "Changes a user's enabled status and invalidates disabled sessions."
  @spec change_status(integer() | String.t(), term()) ::
          {:ok, SysUser.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def change_status(id, status) do
    update_user(id, %{"status" => status})
  end

  @doc "Returns the profile view for an authenticated user."
  def profile(id) do
    case get_user(id) do
      {:ok, user} -> {:ok, user_to_map(user)}
      error -> error
    end
  end

  @doc "Updates editable profile fields without allowing account privilege changes."
  def update_profile(id, attrs) when is_map(attrs) do
    attrs =
      %{}
      |> maybe_put(attrs, "nickname", ["nickName", "nickname"])
      |> maybe_put(attrs, "phoneNumber", ["phoneNumber", "phone_number"])
      |> maybe_put(attrs, "email", ["email"])
      |> maybe_put(attrs, "sex", ["sex"])

    update_user(id, attrs)
  end

  def update_profile(_id, _attrs), do: {:error, invalid_changeset(%SysUser{}, :nickname)}

  @doc "Changes a password after checking the current password."
  def update_password(id, attrs) when is_map(attrs) do
    with {:ok, user} <- get_user(id),
         {:ok, old_password, new_password} <- password_inputs(attrs),
         true <- Bcrypt.verify_pass(old_password, user.password || ""),
         false <- Bcrypt.verify_pass(new_password, user.password || "") do
      case Repo.update(SysUser.password_changeset(user, %{password: new_password})) do
        {:ok, updated} = result ->
          Session.revoke_account(updated.user_id)
          result

        error ->
          error
      end
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, :invalid_password_input} -> {:error, invalid_changeset(%SysUser{}, :password)}
      false -> {:error, :invalid_old_password}
      _ -> {:error, :same_password}
    end
  end

  def update_password(_id, _attrs), do: {:error, invalid_changeset(%SysUser{}, :password)}

  @doc "Updates an avatar URL supplied by the file service."
  def update_avatar(id, avatar) when is_binary(avatar) do
    update_user(id, %{"avatar" => avatar})
  end

  def update_avatar(_id, _avatar), do: {:error, invalid_changeset(%SysUser{}, :avatar)}

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
            case Repo.update(Ecto.Changeset.change(user, deleted: true)) do
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
        Map.has_key?(attrs, json_key) -> Map.put(normalized, atom_key, Map.get(attrs, json_key))
        Map.has_key?(attrs, atom_key) -> Map.put(normalized, atom_key, Map.get(attrs, atom_key))
        true -> normalized
      end
    end)
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer > 0 -> integer
      _ -> nil
    end
  end

  defp parse_positive_integer(_value), do: nil

  defp invalid_changeset(schema, field) do
    Ecto.Changeset.add_error(Ecto.Changeset.change(schema), field, "参数无效")
  end

  defp page_query(query, params) do
    page = positive_integer(params["pageNum"] || params[:page_num], @default_page)
    page_size = positive_integer(params["pageSize"] || params[:page_size], @default_page_size)
    page_size = min(page_size, @max_page_size)

    total = Repo.aggregate(query, :count, :user_id)
    query = query |> limit(^page_size) |> offset(^((page - 1) * page_size))
    rows = Repo.all(query)

    %{total: total, rows: Enum.map(rows, &user_to_map/1)}
  end

  defp filter_integer(query, _field, nil), do: query
  defp filter_integer(query, _field, ""), do: query

  defp filter_integer(query, field, value) do
    case Integer.parse(to_string(value)) do
      {integer, ""} -> where(query, [record], field(record, ^field) == ^integer)
      _ -> query
    end
  end

  defp filter_contains(query, _field, nil), do: query
  defp filter_contains(query, _field, ""), do: query

  defp filter_contains(query, field, value) do
    value = "%#{String.trim(to_string(value))}%"
    where(query, [record], ilike(field(record, ^field), ^value))
  end

  defp positive_integer(nil, default), do: default

  defp positive_integer(value, default) do
    case Integer.parse(to_string(value)) do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
