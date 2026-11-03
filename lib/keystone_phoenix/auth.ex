defmodule KeystonePhoenix.Auth do
  @moduledoc "Local password authentication and refresh token rotation."

  alias KeystonePhoenix.Auth.{Captcha, Session, Token}
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
    with {:ok, user} <- User.get_user_by_username(username),
         true <- user.status == 1,
         true <- Bcrypt.verify_pass(password, user.password || ""),
         {:ok, tokens} <- issue_pair(user, force_login) do
      {:ok, Map.put(tokens, :current_user, User.user_to_map(user))}
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
         true <- Session.valid?(claims["jti"], user_id),
         true <- Session.active?(user_id, claims["jti"]),
         {:ok, user} <- User.get_user(user_id),
         true <- user.status == 1,
         :ok <- Session.revoke(user_id, claims["jti"]),
         {:ok, tokens} <- issue_pair(user, false) do
      {:ok, Map.put(tokens, :current_user, User.user_to_map(user))}
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

  defp issue_pair(user, force_login) do
    with {:ok, refresh} <- Token.issue(user, Token.refresh_type()),
         :ok <- Session.put(refresh.jti, user.user_id, refresh.expires_in) do
      case Session.occupy(user.user_id, refresh.jti, refresh.expires_in, force_login) do
        :ok ->
          issue_access_pair(user, refresh)

        {:error, reason} ->
          Session.delete(refresh.jti)
          {:error, reason}
      end
    else
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
end
