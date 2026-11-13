defmodule KeystonePhoenix.Audit do
  @moduledoc "Helpers for attaching authenticated actor IDs to audit fields."

  alias Ecto.Changeset

  @doc "Adds a canonical UUID actor ID to a changeset when one is available."
  def put_actor(%Changeset{} = changeset, field, actor_id) do
    case canonical_uuid(actor_id) do
      nil -> changeset
      actor_id -> Changeset.put_change(changeset, field, actor_id)
    end
  end

  defp canonical_uuid(value) do
    case KeystonePhoenix.Params.parse_uuid(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end
end
