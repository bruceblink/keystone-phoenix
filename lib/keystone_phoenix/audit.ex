defmodule KeystonePhoenix.Audit do
  @moduledoc "Helpers for attaching authenticated actor IDs to audit fields."

  alias Ecto.Changeset

  @doc "Adds a positive actor ID to a changeset when one is available."
  def put_actor(%Changeset{} = changeset, field, actor_id) do
    case positive_integer(actor_id) do
      nil -> changeset
      actor_id -> Changeset.put_change(changeset, field, actor_id)
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} when number > 0 -> number
      _ -> nil
    end
  end

  defp positive_integer(_value), do: nil
end
