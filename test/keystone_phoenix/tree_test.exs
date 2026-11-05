defmodule KeystonePhoenix.TreeTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Tree

  test "nests rows in input order with one indexing pass" do
    rows = [
      %{"id" => 2, "parentId" => 1, "name" => "child-b"},
      %{"id" => 1, "parentId" => 0, "name" => "root-a"},
      %{"id" => 4, "parentId" => 2, "name" => "grandchild"},
      %{"id" => 3, "parentId" => 1, "name" => "child-c"},
      %{"id" => 5, "parentId" => 0, "name" => "root-b"}
    ]

    assert Tree.nest(rows, "parentId", "id") == [
             %{
               "id" => 1,
               "parentId" => 0,
               "name" => "root-a",
               "children" => [
                 %{
                   "id" => 2,
                   "parentId" => 1,
                   "name" => "child-b",
                   "children" => [%{"id" => 4, "parentId" => 2, "name" => "grandchild"}]
                 },
                 %{"id" => 3, "parentId" => 1, "name" => "child-c"}
               ]
             },
             %{"id" => 5, "parentId" => 0, "name" => "root-b"}
           ]
  end
end
