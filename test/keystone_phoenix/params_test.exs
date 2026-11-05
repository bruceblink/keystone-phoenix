defmodule KeystonePhoenix.ParamsTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Params

  test "parses strict integer request values" do
    assert {:ok, 12} = Params.parse_integer(12)
    assert {:ok, -4} = Params.parse_integer(" -4 ")
    assert :error = Params.parse_integer("12px")
    assert :error = Params.parse_integer(nil)
  end

  test "parses optional non-negative parent IDs" do
    assert {:ok, 0} = Params.non_negative_integer(nil)
    assert {:ok, 3} = Params.non_negative_integer("3")
    assert :error = Params.non_negative_integer("-1")
  end
end
