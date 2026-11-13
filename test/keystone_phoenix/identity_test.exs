defmodule KeystonePhoenix.IdentityTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Identity

  test "generates a canonical UUIDv7" do
    uuid = Identity.v7()
    {:ok, raw} = Identity.dump(uuid)

    <<_timestamp::48, version::4, _random_a::12, variant::2, _random_b::62>> = raw

    assert Identity.canonical?(uuid)
    assert version == 7
    assert variant == 2
  end

  test "generates the shared permission UUIDv5 vector" do
    assert Identity.permission_namespace() == "eb754ae2-49de-5e5f-87ef-1fa5eded86d8"

    assert Identity.permission_id("user:read") ==
             "950c8856-7230-5a63-937f-472185c3a8c4"
  end

  test "round trips PostgreSQL UUID bytes" do
    uuid = "018f0f2a-6e28-7abc-8def-0123456789ab"

    assert {:ok, raw} = Identity.dump(uuid)
    assert byte_size(raw) == 16
    assert Identity.load(raw) == {:ok, uuid}
  end

  test "rejects non-canonical UUID and permission values" do
    refute Identity.canonical?("018F0F2A-6E28-7ABC-8DEF-0123456789AB")
    assert_raise ArgumentError, fn -> Identity.canonical!("not-a-uuid") end
    assert_raise ArgumentError, fn -> Identity.permission_id("system:user:read") end
    assert :error = Identity.dump("018f0f2a-6e28-7abc-8def-0123456789a")
    assert :error = Identity.load(<<0::120>>)
  end
end
