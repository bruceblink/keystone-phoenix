defmodule KeystonePhoenix.Auth do
  @moduledoc "Local password authentication and refresh token rotation."

  alias KeystonePhoenix.Auth.{Captcha, Mfa, Session, Token}
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Params
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

  @doc "Authenticates an API login and returns a short-lived MFA challenge when required."
  @spec login_api(
          String.t(),
          String.t(),
          boolean(),
          String.t() | nil,
          String.t() | nil,
          String.t()
        ) ::
          {:ok, map()} | {:mfa_required, map()} | {:error, atom()}
  def login_api(username, password, force_login, captcha_code, captcha_key, client_id \\ "web")

  def login_api(
        username,
        password,
        force_login,
        captcha_code,
        captcha_key,
        client_id
      )
      when is_binary(username) and is_binary(password) and is_boolean(force_login) and
             is_binary(client_id) do
    with :ok <- Captcha.validate(captcha_code, captcha_key),
         {:ok, plaintext_password} <- Token.decrypt_password(password),
         {:ok, candidate} <- User.get_user_by_username(username),
         {:ok, result} <-
           Session.with_user_lock(candidate.user_id, fn ->
             authenticate_api_login(
               candidate.user_id,
               plaintext_password,
               force_login,
               client_id
             )
           end) do
      case result do
        {:mfa_required, challenge} -> {:mfa_required, challenge}
        {:authenticated, tokens} -> {:ok, tokens}
      end
    else
      {:error, reason}
      when reason in [:captcha_required, :captcha_invalid, :captcha_expired, :unavailable] ->
        {:error, reason}

      {:error, :mfa_enrollment_required} ->
        {:error, :mfa_enrollment_required}

      {:error, :validation_failed} ->
        {:error, :validation_failed}

      {:error, reason} when reason in [:already_logged_in, :token_configuration] ->
        {:error, reason}

      _ ->
        {:error, :invalid_credentials}
    end
  end

  def login_api(_username, _password, _force_login, _captcha_code, _captcha_key, _client_id),
    do: {:error, :invalid_credentials}

  @doc "Completes a login MFA challenge and creates the authenticated session."
  @spec complete_mfa_login(String.t(), String.t(), String.t(), String.t(), boolean(), tuple()) ::
          {:ok, map()} | {:error, atom()}
  def complete_mfa_login(username, challenge_id, client_id, code, force_login, ip_address) do
    with {:ok, user} <- User.get_user_by_username(username),
         true <- user.status == 1,
         {:ok, result} <-
           Session.with_user_lock(user.user_id, fn ->
             with {:ok, verification} <-
                    Mfa.verify_login(user.user_id, challenge_id, client_id, code, ip_address),
                  {:ok, tokens} <- issue_pair(user, force_login, client_id) do
               {:ok,
                %{
                  tokens: Map.put(tokens, :current_user, current_login_user(user)),
                  verification: verification
                }}
             end
           end) do
      {:ok, result}
    else
      false -> {:error, :invalid_credentials}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Returns the active session context represented by an access token."
  @spec session_context(String.t()) :: {:ok, map()} | {:error, :invalid_token}
  def session_context(token) when is_binary(token) do
    with {:ok, claims} <- Token.verify(token, Token.access_type()),
         {:ok, session_id} <- canonical_session_id(claims["sid"]),
         {:ok, user} <- authenticate_access_token(token) do
      {:ok, %{user: user, session_id: session_id, client_id: "web"}}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def session_context(_token), do: {:error, :invalid_token}

  @doc "Updates a user's MFA requirement and revokes sessions after a policy change."
  @spec set_mfa_policy(String.t(), boolean()) :: {:ok, map()} | {:error, atom()}
  def set_mfa_policy(user_id, required) when is_boolean(required) do
    with {:ok, user_id} <- parse_user_id(user_id),
         {:ok, :ok} <- Mfa.set_required(user_id, required) do
      Session.revoke_account(user_id)
      {:ok, %{"userId" => user_id, "required" => required}}
    else
      {:error, :invalid_token} -> {:error, :validation_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  def set_mfa_policy(_user_id, _required), do: {:error, :validation_failed}

  @doc "Verifies the current password before rotating MFA recovery codes."
  @spec rotate_mfa_recovery_codes(map(), String.t()) :: {:ok, list()} | {:error, atom()}
  def rotate_mfa_recovery_codes(user, current_password)
      when is_map(user) and is_binary(current_password) do
    if Bcrypt.verify_pass(current_password, Map.get(user, :password) || "") do
      Mfa.rotate_recovery_codes(user.user_id)
    else
      {:error, :invalid_credentials}
    end
  end

  def rotate_mfa_recovery_codes(_user, _current_password),
    do: {:error, :invalid_credentials}

  defp authenticate_api_login(user_id, plaintext_password, force_login, client_id) do
    with {:ok, user} <- User.get_user(user_id),
         true <- user.status == 1,
         true <- Bcrypt.verify_pass(plaintext_password, user.password || ""),
         {:ok, preparation} <- Mfa.prepare_login(user.user_id, client_id) do
      case preparation do
        %{required: true, challenge: challenge} when is_map(challenge) ->
          {:ok, {:mfa_required, challenge}}

        %{required: true, challenge: nil} ->
          {:error, :mfa_enrollment_required}

        _ ->
          with {:ok, tokens} <- issue_pair(user, force_login, client_id) do
            {:ok, {:authenticated, Map.put(tokens, :current_user, current_login_user(user))}}
          end
      end
    else
      {:error, :not_found} -> {:error, :invalid_credentials}
      false -> {:error, :invalid_credentials}
      {:error, reason} -> {:error, reason}
    end
  end

  defp canonical_session_id(value) do
    case parse_user_id(value) do
      {:ok, id} -> {:ok, id}
      _ -> {:error, :invalid_token}
    end
  end

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
         session_id when is_binary(session_id) <- claims["sid"],
         {:ok, tokens} <-
           Session.rotate(user_id, jti, session_id, refresh_token, fn user, session ->
             issue_pair_for_session(user, session)
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
         {:ok, _user_id} <- parse_user_id(claims["sub"]),
         session_id when is_binary(session_id) <- claims["sid"] do
      Session.revoke_session(session_id)
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
         permission_version when is_integer(permission_version) <- claims["permission_version"],
         true <- Session.active?(user_id, session_id),
         {:ok, user} <- User.get_user(user_id),
         true <- user.status == 1 and user.permission_version == permission_version do
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

  defp issue_pair(user, force_login, client_id \\ "web") do
    session_id = Session.new_session_id()

    with {:ok, refresh} <- Token.issue(user, Token.refresh_type(), session_id),
         :ok <-
           Session.occupy(
             user.user_id,
             refresh.jti,
             refresh.expires_in,
             force_login,
             session_id,
             client_id,
             refresh.token
           ) do
      issue_access_pair(user, refresh, session_id)
    else
      {:error, :already_logged_in} -> {:error, :already_logged_in}
      {:error, {:token_configuration, _reason}} -> {:error, :token_configuration}
      {:error, :unavailable} -> {:error, :unavailable}
    end
  end

  defp issue_access_pair(user, refresh, session_id) do
    case Token.issue(user, Token.access_type(), session_id) do
      {:ok, access} ->
        {:ok,
         %{
           token: access.token,
           refresh_token: refresh.token,
           expires_in: access.expires_in,
           refresh_expires_in: refresh.expires_in,
           refresh_jti: refresh.jti,
           session_id: session_id
         }}

      {:error, {:token_configuration, _reason}} ->
        Session.revoke_session(session_id)
        {:error, :token_configuration}
    end
  end

  defp issue_pair_for_session(user, session) do
    refresh_ttl = DateTime.diff(session.refresh_expires_at, DateTime.utc_now(), :second)

    if refresh_ttl <= 0 do
      {:error, :invalid_refresh_token}
    else
      with {:ok, refresh} <-
             Token.issue(user, Token.refresh_type(), session.id, refresh_ttl),
           {:ok, access} <- Token.issue(user, Token.access_type(), session.id) do
        {:ok,
         %{
           token: access.token,
           refresh_token: refresh.token,
           expires_in: access.expires_in,
           refresh_expires_in: refresh.expires_in,
           refresh_jti: refresh.jti,
           session_id: session.id
         }}
      end
    end
  end

  defp parse_user_id(value) when is_binary(value) do
    case Params.parse_uuid(value) do
      {:ok, user_id} -> {:ok, user_id}
      :error -> {:error, :invalid_token}
    end
  end

  defp parse_user_id(_value), do: {:error, :invalid_token}

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
