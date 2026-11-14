defmodule KeystonePhoenix.Auth.Passkey.ChallengeTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Auth.Passkey.Challenge

  test "challenge can be consumed only once" do
    challenge =
      Ithibati.Identity.Passkeys.registration_challenge("localhost", "http://localhost:4000")

    {:ok, challenge_id} = Challenge.issue(challenge)
    retained = Ithibati.Identity.Passkeys.retain_challenge(challenge)

    assert challenge_id == Challenge.id(retained)
    assert :ok = Challenge.consume(retained)
    assert {:error, :passkey_challenge_invalid} = Challenge.consume(retained)
  end
end
