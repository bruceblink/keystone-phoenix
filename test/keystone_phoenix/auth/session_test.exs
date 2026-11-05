defmodule KeystonePhoenix.Auth.SessionTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Auth.Session

  @tag :integration
  test "list_active returns Redis-backed sessions" do
    assert {:ok, sessions} = Session.list_active()
    assert is_list(sessions)

    assert Enum.all?(sessions, fn session ->
             is_binary(session.jti) and is_integer(session.user_id) and session.user_id > 0
           end)
  end
end
