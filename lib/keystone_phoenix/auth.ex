defmodule KeystonePhoenix.Auth do
  @moduledoc "Local password authentication and refresh token rotation."

  alias KeystonePhoenix.Auth.{Session, Token}
  alias KeystonePhoenix.User

  @spec login(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def login(username, password) when is_binary(username) and is_binary(password) do
    with {:ok, user} <- User.get_user_by_username(username),
         true <- user.status == 1,
         true <- Bcrypt.verify_pass(password, user.password || ""),
         {:ok, tokens} <- issue_pair(user) do
      {:ok, Map.put(tokens, :current_user, User.user_to_map(user))}
    else
      {:error, reason} when reason in [:unavailable, :token_configuration] -> {:error, reason}
      _ -> {:error, :invalid_credentials}
    end
  end

  def login(_username, _password), do: {:error, :invalid_credentials}

  @spec refresh(String.t()) :: {:ok, map()} | {:error, atom()}
  def refresh(refresh_token) when is_binary(refresh_token) do
    with {:ok, claims} <- Token.verify(refresh_token, Token.refresh_type()),
         {:ok, user_id} <- parse_user_id(claims["sub"]),
         true <- Session.valid?(claims["jti"], user_id),
         {:ok, user} <- User.get_user(user_id),
         true <- user.status == 1,
         :ok <- Session.delete(claims["jti"]),
         {:ok, tokens} <- issue_pair(user) do
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
         jti when is_binary(jti) <- claims["jti"] do
      Session.delete(jti)
    else
      _ -> :ok
    end
  end

  def logout(_refresh_token), do: :ok

  @spec authenticate_access_token(String.t()) :: {:ok, map()} | {:error, :invalid_token}
  def authenticate_access_token(token) do
    with {:ok, claims} <- Token.verify(token, Token.access_type()),
         {:ok, user_id} <- parse_user_id(claims["sub"]),
         {:ok, user} <- User.get_user(user_id),
         true <- user.status == 1 do
      {:ok, user}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp issue_pair(user) do
    with {:ok, access} <- Token.issue(user, Token.access_type()),
         {:ok, refresh} <- Token.issue(user, Token.refresh_type()),
         :ok <- Session.put(refresh.jti, user.user_id, refresh.expires_in) do
      {:ok,
       %{
         token: access.token,
         refresh_token: refresh.token,
         expires_in: access.expires_in,
         refresh_expires_in: refresh.expires_in
       }}
    else
      {:error, {:token_configuration, _reason}} -> {:error, :token_configuration}
      {:error, :unavailable} -> {:error, :unavailable}
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
