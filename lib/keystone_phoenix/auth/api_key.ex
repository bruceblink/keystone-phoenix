defmodule KeystonePhoenix.Auth.ApiKey do
  @moduledoc """
  API Key 和服务主体领域服务。

  明文只在签发或轮换的返回值中出现一次。数据库保存 `ks_live_` 凭据的 SHA-256
  摘要、短前缀、服务主体、权限范围和撤销状态。API Key Principal 只能用于业务
  权限和数据范围判断，密码、MFA 和 API Key 管理入口必须由 PEP 另行拒绝。
  """

  import Ecto.Query

  alias KeystonePhoenix.Auth.ApiKey.{Key, RateLimiter, ServiceSubject}
  alias KeystonePhoenix.Authz.Command
  alias KeystonePhoenix.Authz.PermissionCatalog
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  @prefix "ks_live_"
  @secret_bytes 32
  @key_prefix_bytes 8
  @max_expiry_seconds 90 * 24 * 60 * 60
  @last_used_interval_seconds 60

  @doc "签发 API Key，并返回一次明文凭据。"
  def issue(user_id, name, scopes, expires_at \\ nil) do
    with {:ok, user_id} <- canonical_id(user_id),
         {:ok, name} <- normalize_name(name),
         {:ok, scopes} <- normalize_scopes(scopes),
         :ok <- validate_expiry(expires_at) do
      run_transaction(fn ->
        user = lock_active_user!(user_id)
        permissions = Menu.permissions_for_user(user)
        :ok = ensure_scope_subset(scopes, permissions)
        subject_id = ensure_subject!(user_id)
        issue_locked!(user, subject_id, name, scopes, expires_at)
      end)
    end
  end

  @doc "通过显式人类授权上下文签发 API Key；API Key 主体不能进入管理命令。"
  def issue(user_id, name, scopes, expires_at, options) when is_list(options) do
    with {:ok, user_id} <- canonical_id(user_id),
         :ok <- authorize_management(options, "api-key:create", user_id) do
      issue(user_id, name, scopes, expires_at)
    end
  end

  @doc "使用 API Key 构建机器主体；不返回密码、MFA 或完整凭据。"
  def authenticate(value, ip_address \\ nil) do
    with :ok <- validate_value(value),
         false <- RateLimiter.blocked?(value, ip_address) do
      result =
        case Repo.one(active_key_query(key_hash(value), DateTime.utc_now())) do
          nil -> {:error, :invalid_credential}
          key -> authenticate_record(key, value, ip_address)
        end

      after_authentication(result, value, ip_address)
    else
      true -> {:error, :rate_limited}
      {:error, _} = error -> error
    end
  rescue
    _error -> {:error, :authorization_unavailable}
  end

  @doc "列出用户拥有的 API Key 元数据，不包含凭据摘要。"
  def list(user_id) do
    with {:ok, user_id} <- canonical_id(user_id) do
      Repo.all(from key in Key, where: key.user_id == ^user_id, order_by: [desc: key.inserted_at])
      |> Enum.map(&metadata/1)
    else
      {:error, _} -> []
    end
  end

  @doc "通过显式人类授权上下文查询本人 API Key 元数据。"
  def list(user_id, options) when is_list(options) do
    with {:ok, user_id} <- canonical_id(user_id),
         :ok <- authorize_management(options, "api-key:read", user_id) do
      {:ok, list(user_id)}
    end
  end

  @doc "撤销指定用户拥有的 API Key；重复撤销保持成功。"
  def revoke(user_id, key_id) do
    with {:ok, user_id} <- canonical_id(user_id),
         {:ok, key_id} <- canonical_id(key_id) do
      case run_transaction(fn ->
             key = lock_key!(user_id, key_id)

             key
             |> Ecto.Changeset.change(
               revoked_at: key.revoked_at || DateTime.utc_now(),
               revoked_reason: key.revoked_reason || "revoked by owner"
             )
             |> Repo.update!()

             :ok
           end) do
        {:ok, :ok} -> :ok
        other -> other
      end
    end
  end

  @doc "通过显式人类授权上下文撤销本人的 API Key。"
  def revoke(user_id, key_id, options) when is_list(options) do
    with {:ok, user_id} <- canonical_id(user_id),
         :ok <- authorize_management(options, "api-key:revoke", user_id) do
      revoke(user_id, key_id)
    end
  end

  @doc "锁定旧记录后签发替代凭据并原子撤销旧凭据。"
  def rotate(user_id, key_id) do
    with {:ok, user_id} <- canonical_id(user_id),
         {:ok, key_id} <- canonical_id(key_id) do
      run_transaction(fn ->
        user = lock_active_user!(user_id)
        current = lock_key!(user_id, key_id)
        if current.revoked_at, do: Repo.rollback(:already_revoked)

        permissions = Menu.permissions_for_user(user)
        scopes = current.scopes |> split_scopes() |> intersect_permissions(permissions)
        if scopes == [], do: Repo.rollback(:scope_exceeds_permissions)

        replacement =
          issue_locked!(user, current.subject_id, current.name, scopes, current.expires_at)

        now = DateTime.utc_now()

        current
        |> Ecto.Changeset.change(
          revoked_at: now,
          revoked_reason: "rotated",
          rotated_to: replacement.id
        )
        |> Repo.update!()

        replacement
      end)
    end
  end

  @doc "通过显式人类授权上下文轮换本人的 API Key。"
  def rotate(user_id, key_id, options) when is_list(options) do
    with {:ok, user_id} <- canonical_id(user_id),
         :ok <- authorize_management(options, "api-key:rotate", user_id) do
      rotate(user_id, key_id)
    end
  end

  @doc "检查请求范围是否属于用户当前可授予的已登记权限。"
  def scope_intersection(scopes, permissions) do
    with {:ok, requested} <- normalize_scopes(scopes) do
      {:ok, intersect_permissions(requested, permissions)}
    end
  end

  defp authenticate_record(key, _value, ip_address) do
    with subject_id when is_binary(subject_id) <- key.subject_id,
         %ServiceSubject{enabled: true} = subject <- Repo.get(ServiceSubject, subject_id),
         %SysUser{status: 1, deleted: false} = user <- Repo.get(SysUser, key.user_id),
         scopes when scopes != [] <-
           intersect_permissions(split_scopes(key.scopes), Menu.permissions_for_user(user)) do
      touch_last_used(key, ip_address)

      {:ok,
       %{
         key_id: key.id,
         credential_id: key.id,
         subject_type: "SERVICE_SUBJECT",
         subject_id: subject.id,
         user_id: user.user_id,
         username: user.username,
         role_id: user.role_id,
         dept_id: user.dept_id,
         credential_type: "API_KEY",
         permissions: scopes,
         scopes: scopes,
         approved_scopes: scopes
       }}
    else
      _ -> {:error, :invalid_credential}
    end
  end

  defp touch_last_used(key, ip_address) do
    interval =
      Application.get_env(
        :keystone_phoenix,
        :api_key_last_used_update_interval_seconds,
        @last_used_interval_seconds
      )

    if is_integer(interval) and interval >= 0 do
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, -interval, :second)
      ip = RateLimiter.normalize_ip(ip_address)

      Repo.update_all(
        from(entry in Key,
          where:
            entry.id == ^key.id and
              (is_nil(entry.last_used_at) or entry.last_used_at <= ^cutoff)
        ),
        set: [last_used_at: now, last_used_ip: ip]
      )
    else
      raise ArgumentError, "API key last-used update interval must be non-negative"
    end
  end

  defp after_authentication({:ok, _value} = result, value, _ip_address) do
    _ = RateLimiter.clear(value)
    result
  end

  defp after_authentication({:error, :invalid_credential} = result, value, ip_address) do
    _ = RateLimiter.record_failure(value, ip_address)
    result
  end

  defp issue_locked!(user, subject_id, name, scopes, expires_at) do
    prefix = random(@key_prefix_bytes)
    secret = random(@secret_bytes)
    value = @prefix <> prefix <> "_" <> secret

    key =
      %Key{}
      |> Key.changeset(%{
        id: KeystonePhoenix.Identity.v7(),
        user_id: user.user_id,
        subject_id: subject_id,
        created_by: user.user_id,
        name: name,
        key_prefix: prefix,
        key_hash: key_hash(value),
        scopes: Enum.join(scopes, " "),
        expires_at: expires_at
      })
      |> Repo.insert!()

    %{
      id: key.id,
      name: name,
      prefix: prefix,
      api_key: value,
      scopes: scopes,
      expires_at: expires_at
    }
  end

  defp ensure_subject!(user_id) do
    code = "user:" <> user_id

    case Repo.get_by(ServiceSubject, code: code) do
      %ServiceSubject{id: id} ->
        id

      nil ->
        attrs = %{
          id: KeystonePhoenix.Identity.v7(),
          code: code,
          name: "User API keys: " <> user_id,
          owner_user_id: user_id,
          enabled: true
        }

        {count, _} =
          Repo.insert_all(
            ServiceSubject,
            [
              Map.merge(attrs, %{inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()})
            ],
            on_conflict: :nothing,
            conflict_target: [:code]
          )

        if count == 0 do
          Repo.get_by!(ServiceSubject, code: code).id
        else
          attrs.id
        end
    end
  end

  defp lock_active_user!(user_id) do
    case Repo.one(
           from user in SysUser,
             where: user.user_id == ^user_id and user.status == 1 and user.deleted == false,
             lock: "FOR UPDATE"
         ) do
      nil -> Repo.rollback(:user_not_found)
      user -> user
    end
  end

  defp lock_key!(user_id, key_id) do
    case Repo.one(
           from key in Key,
             where: key.user_id == ^user_id and key.id == ^key_id,
             lock: "FOR UPDATE"
         ) do
      nil -> Repo.rollback(:not_found)
      key -> key
    end
  end

  defp active_key_query(hash, now) do
    from key in Key,
      where:
        key.key_hash == ^hash and is_nil(key.revoked_at) and
          (is_nil(key.expires_at) or key.expires_at > ^now)
  end

  defp metadata(key) do
    %{
      id: key.id,
      name: key.name,
      prefix: key.key_prefix,
      scopes: split_scopes(key.scopes),
      expires_at: key.expires_at,
      revoked_at: key.revoked_at,
      last_used_at: key.last_used_at,
      created_at: key.inserted_at
    }
  end

  defp ensure_scope_subset(scopes, permissions) do
    if Enum.all?(scopes, &(&1 in permissions)),
      do: :ok,
      else: Repo.rollback(:scope_exceeds_permissions)
  end

  defp intersect_permissions(scopes, permissions) do
    allowed = MapSet.new(List.wrap(permissions) |> Enum.map(&normalize_scope/1))
    scopes |> Enum.filter(&MapSet.member?(allowed, &1)) |> Enum.uniq() |> Enum.sort()
  end

  defp normalize_scopes(scopes) when is_list(scopes) do
    normalized = Enum.map(scopes, &normalize_scope/1)

    cond do
      normalized == [] or Enum.any?(normalized, &(&1 == "")) ->
        {:error, :validation_failed}

      Enum.any?(normalized, &(not PermissionCatalog.registered?(&1))) ->
        {:error, :validation_failed}

      true ->
        {:ok, Enum.uniq(normalized) |> Enum.sort()}
    end
  end

  defp normalize_scopes(_scopes), do: {:error, :validation_failed}

  defp normalize_scope(value) when is_binary(value), do: String.trim(value) |> String.downcase()
  defp normalize_scope(_value), do: ""

  defp split_scopes(value) when is_binary(value),
    do: value |> String.split(" ", trim: true) |> Enum.uniq() |> Enum.sort()

  defp split_scopes(_value), do: []

  defp normalize_name(value) when is_binary(value) do
    value = String.trim(value)

    if value != "" and String.length(value) <= 128,
      do: {:ok, value},
      else: {:error, :validation_failed}
  end

  defp normalize_name(_value), do: {:error, :validation_failed}

  defp validate_expiry(nil), do: :ok

  defp validate_expiry(%DateTime{} = expires_at) do
    now = DateTime.utc_now()

    if DateTime.compare(expires_at, now) in [:gt, :eq] and
         DateTime.compare(expires_at, DateTime.add(now, @max_expiry_seconds, :second)) != :gt,
       do: :ok,
       else: {:error, :validation_failed}
  end

  defp validate_expiry(_value), do: {:error, :validation_failed}

  defp validate_value(value) when is_binary(value) do
    if Regex.match?(~r/\Aks_live_[A-Za-z0-9_-]{8,24}_[A-Za-z0-9_-]{32,64}\z/, value),
      do: :ok,
      else: {:error, :invalid_credential}
  end

  defp validate_value(_value), do: {:error, :invalid_credential}

  # API Key 管理命令只接受当前用户的 SELF 关系，并拒绝机器凭据递归管理。
  defp authorize_management(options, permission, user_id) do
    with {:ok, principal} <- Command.principal(options),
         false <- api_key_principal?(principal),
         :ok <-
           Command.authorize_resource(options, permission, :api_key, %{target_id: user_id}) do
      :ok
    else
      true -> {:error, :permission_denied}
      {:error, reason} -> {:error, reason}
    end
  end

  defp api_key_principal?(principal) when is_map(principal) do
    Map.get(principal, :credential_type, Map.get(principal, "credential_type")) == "API_KEY" or
      Map.get(principal, :credentialType, Map.get(principal, "credentialType")) == "API_KEY"
  end

  defp key_hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp random(bytes), do: :crypto.strong_rand_bytes(bytes) |> Base.url_encode64(padding: false)

  defp canonical_id(value) do
    if KeystonePhoenix.Identity.canonical?(value),
      do: {:ok, value},
      else: {:error, :validation_failed}
  end

  defp run_transaction(function) do
    case Repo.transaction(function) do
      {:ok, {:ok, value}} -> {:ok, value}
      {:ok, {:error, reason}} -> {:error, reason}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end
end
