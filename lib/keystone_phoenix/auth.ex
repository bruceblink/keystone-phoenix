defmodule KeystonePhoenix.Auth do
  @moduledoc "Local password authentication and refresh token rotation."

  alias KeystonePhoenix.Auth.{Captcha, Session, Token}
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.User

  @spec login(String.t(), String.t(), boolean(), String.t() | nil, String.t() | nil) ::
          {:ok, map()} | {:error, atom()}
  def login(username, password, force_login \\ false, captcha_code \\ nil, captcha_key \\ nil)

  def login(username, password, force_login, captcha_code, captcha_key)
      when is_binary(username) and is_binary(password) and is_boolean(force_login) do
    with :ok <- Captcha.validate(captcha_code, captcha_key),
         {:ok, plaintext_password} <- Token.decrypt_password(password) do
      login_plaintext(username, plaintext_password, force_login)
    else
      {:error, reason}
      when reason in [:captcha_required, :captcha_invalid, :captcha_expired, :unavailable] ->
        {:error, reason}

      _ ->
        {:error, :invalid_credentials}
    end
  end

  def login(_username, _password, _force_login, _captcha_code, _captcha_key),
    do: {:error, :invalid_credentials}

  @doc "Authenticates a password already received over a LiveView session."
  @spec login_plaintext(String.t(), String.t(), boolean()) :: {:ok, map()} | {:error, atom()}
  def login_plaintext(username, password, force_login \\ false)

  def login_plaintext(username, password, force_login)
      when is_binary(username) and is_binary(password) and is_boolean(force_login) do
    with {:ok, candidate} <- User.get_user_by_username(username),
         {:ok, tokens} <-
           Session.with_user_lock(candidate.user_id, fn ->
             with {:ok, user} <- User.get_user(candidate.user_id),
                  true <- user.status == 1,
                  true <- Bcrypt.verify_pass(password, user.password || ""),
                  {:ok, tokens} <- issue_pair(user, force_login) do
               {:ok, Map.put(tokens, :current_user, current_login_user(user))}
             else
               {:error, :not_found} -> {:error, :invalid_credentials}
               false -> {:error, :invalid_credentials}
               {:error, reason} -> {:error, reason}
             end
           end) do
      {:ok, tokens}
    else
      {:error, reason} when reason in [:unavailable, :token_configuration, :already_logged_in] ->
        {:error, reason}

      _ ->
        {:error, :invalid_credentials}
    end
  end

  def login_plaintext(_username, _password, _force_login), do: {:error, :invalid_credentials}

  @spec refresh(String.t()) :: {:ok, map()} | {:error, atom()}
  def refresh(refresh_token) when is_binary(refresh_token) do
    with {:ok, claims} <- Token.verify(refresh_token, Token.refresh_type()),
         {:ok, user_id} <- parse_user_id(claims["sub"]),
         jti when is_binary(jti) <- claims["jti"],
         {:ok, tokens} <-
           Session.rotate(user_id, jti, fn user ->
             with {:ok, tokens} <- issue_pair(user, false) do
               {:ok, Map.put(tokens, :current_user, current_login_user(user))}
             end
           end) do
      {:ok, tokens}
    else
      {:error, :unavailable} -> {:error, :unavailable}
      _ -> {:error, :invalid_refresh_token}
    end
  end

  def refresh(_refresh_token), do: {:error, :invalid_refresh_token}

  @spec logout(String.t()) :: :ok
  def logout(refresh_token) when is_binary(refresh_token) do
    with {:ok, claims} <- Token.verify(refresh_token, Token.refresh_type()),
         {:ok, user_id} <- parse_user_id(claims["sub"]),
         jti when is_binary(jti) <- claims["jti"] do
      Session.revoke(user_id, jti)
    else
      _ -> :ok
    end
  end

  def logout(_refresh_token), do: :ok

  @doc "Revokes the refresh session referenced by an authenticated access token."
  @spec logout_access(String.t()) :: :ok
  def logout_access(token) when is_binary(token) do
    with {:ok, claims} <- Token.verify(token, Token.access_type()),
         {:ok, user_id} <- parse_user_id(claims["sub"]),
         session_id when is_binary(session_id) <- claims["sid"] do
      Session.revoke(user_id, session_id)
    else
      _ -> :ok
    end
  end

  def logout_access(_token), do: :ok

  @spec authenticate_access_token(String.t()) :: {:ok, map()} | {:error, :invalid_token}
  def authenticate_access_token(token) do
    with {:ok, claims} <- Token.verify(token, Token.access_type()),
         {:ok, user_id} <- parse_user_id(claims["sub"]),
         session_id when is_binary(session_id) <- claims["sid"],
         true <- Session.active?(user_id, session_id),
         {:ok, user} <- User.get_user(user_id),
         true <- user.status == 1 do
      {:ok, user}
    else
      _ -> {:error, :invalid_token}
    end
  end

  @doc "Builds the frontend-compatible current login user payload."
  @spec current_login_user(map()) :: map()
  def current_login_user(user) do
    {role_key, permissions} = role_permissions(user)

    %{
      "userInfo" => User.user_to_map_with_relations(user),
      "roleKey" => role_key,
      "permissions" => permissions
    }
  end

  defp issue_pair(user, force_login) do
    with {:ok, refresh} <- Token.issue(user, Token.refresh_type()),
         :ok <- Session.occupy(user.user_id, refresh.jti, refresh.expires_in, force_login) do
      issue_access_pair(user, refresh)
    else
      {:error, :already_logged_in} -> {:error, :already_logged_in}
      {:error, {:token_configuration, _reason}} -> {:error, :token_configuration}
      {:error, :unavailable} -> {:error, :unavailable}
    end
  end

  defp issue_access_pair(user, refresh) do
    case Token.issue(user, Token.access_type(), refresh.jti) do
      {:ok, access} ->
        {:ok,
         %{
           token: access.token,
           refresh_token: refresh.token,
           expires_in: access.expires_in,
           refresh_expires_in: refresh.expires_in
         }}

      {:error, {:token_configuration, _reason}} ->
        Session.revoke(user.user_id, refresh.jti)
        {:error, :token_configuration}
    end
  end

  defp parse_user_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {user_id, ""} when user_id > 0 -> {:ok, user_id}
      _ -> {:error, :invalid_token}
    end
  end

  defp parse_user_id(_value), do: {:error, :invalid_token}

  defp role_permissions(%{is_admin: true, role_id: role_id} = user)
       when is_integer(role_id) and role_id > 0,
       do: role_permissions_for_role(user)

  defp role_permissions(%{is_admin: true}), do: {"admin", ["*:*:*"]}

  defp role_permissions(user), do: role_permissions_for_role(user)

  defp role_permissions_for_role(user) do
    role_key =
      case user.role_id do
        nil ->
          ""

        role_id ->
          case Role.get_role(role_id) do
            {:ok, role} -> role.role_key
            {:error, :not_found} -> ""
          end
      end

    {role_key, Menu.permissions_for_user(user)}
  end
end
