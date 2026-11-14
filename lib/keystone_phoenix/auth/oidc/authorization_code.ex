defmodule KeystonePhoenix.Auth.Oidc.AuthorizationCode do
  @moduledoc "OIDC provider 授权码的一次性消费记录。"

  import Ecto.Query

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo

  @schema KeystonePhoenix.Auth.Oidc.AuthorizationCodeRecord

  @doc "在数据库中原子登记并消费 provider 授权码；重复或过期请求只允许失败。"
  def consume(code, attrs) when is_binary(code) and is_map(attrs) do
    now = DateTime.utc_now()
    code_hash = :crypto.hash(:sha256, code)
    state_hash = :crypto.hash(:sha256, attrs.state)

    Repo.transaction(fn ->
      Repo.insert_all(
        @schema,
        [
          %{
            id: Identity.v7(),
            code_hash: code_hash,
            provider: attrs.provider,
            client_id: attrs.client_id,
            redirect_uri: attrs.redirect_uri,
            state_hash: state_hash,
            created_at: now,
            expires_at: DateTime.add(now, attrs.ttl_seconds, :second)
          }
        ],
        on_conflict: :nothing,
        conflict_target: :code_hash
      )

      query =
        from record in @schema,
          where:
            record.code_hash == ^code_hash and record.state_hash == ^state_hash and
              is_nil(record.consumed_at) and
              record.expires_at > ^now

      case Repo.update_all(query, set: [consumed_at: now]) do
        {1, _} -> :ok
        _ -> Repo.rollback(:authorization_code_replayed)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :authorization_code_unavailable}
  end
end
