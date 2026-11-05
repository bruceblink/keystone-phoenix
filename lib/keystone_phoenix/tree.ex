defmodule KeystonePhoenix.Tree do
  @moduledoc "Builds ordered parent-child trees from flat maps."

  @doc "Nests rows by parent while preserving the input order at every level."
  @spec nest([map()], String.t(), String.t(), term()) :: [map()]
  def nest(rows, parent_key, id_key, root_parent \\ 0) when is_list(rows) do
    children_by_parent = Enum.group_by(rows, &Map.get(&1, parent_key))

    children_by_parent
    |> Map.get(root_parent, [])
    |> Enum.map(&attach_children(&1, children_by_parent, id_key))
  end

  defp attach_children(row, children_by_parent, id_key) do
    children =
      children_by_parent
      |> Map.get(Map.get(row, id_key), [])
      |> Enum.map(&attach_children(&1, children_by_parent, id_key))

    if children == [], do: row, else: Map.put(row, "children", children)
  end
end
