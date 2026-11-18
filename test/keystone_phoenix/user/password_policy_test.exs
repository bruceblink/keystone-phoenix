defmodule KeystonePhoenix.User.PasswordPolicyTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset, only: [get_change: 2]

  alias KeystonePhoenix.User.PasswordPolicy
  alias KeystonePhoenix.User.SysUser

  @test_policy %{
    min_length: 8,
    require_uppercase: false,
    require_lowercase: false,
    require_digit: false,
    require_special: false,
    disallowed: "test-only-disallowed"
  }

  test "production defaults and test settings match the Native profiles" do
    assert PasswordPolicy.production_defaults() == %{
             min_length: 12,
             require_uppercase: true,
             require_lowercase: true,
             require_digit: true,
             require_special: true,
             disallowed: "password,password1,1234567890,qwerty123,admin"
           }

    assert PasswordPolicy.current_config() == @test_policy

    assert :ok =
             PasswordPolicy.validate(
               "alice",
               "S3cure!Passw0rd",
               PasswordPolicy.production_defaults()
             )
  end

  test "counts Unicode code points and applies Native character categories" do
    combined = "A1!a" <> String.duplicate("e\u0301", 4)
    assert String.length(combined) == 8
    assert length(String.to_charlist(combined)) == 12
    assert :ok = PasswordPolicy.validate(nil, combined, PasswordPolicy.production_defaults())

    short = "A1!a" <> String.duplicate("e\u0301", 3) <> "x"
    assert length(String.to_charlist(short)) == 11

    assert {:error, :password_too_short} =
             PasswordPolicy.validate(nil, short, PasswordPolicy.production_defaults())

    # U+216B has the Unicode Uppercase property; Native Character.isUpperCase accepts it.
    assert :ok =
             PasswordPolicy.validate(
               nil,
               "Ⅻa1!" <> String.duplicate("x", 8),
               PasswordPolicy.production_defaults()
             )

    # Java Character.isLetterOrDigit excludes letter-number and other-number categories.
    assert :ok =
             PasswordPolicy.validate(
               nil,
               "Aa123456789Ⅻ",
               PasswordPolicy.production_defaults()
             )
  end

  test "rejects missing categories, weak values, and passwords containing the username" do
    strict = PasswordPolicy.production_defaults()

    assert {:error, :password_contains_username} =
             PasswordPolicy.validate("alice", "Alice!23456789", strict)

    disallowed_password = Map.put(@test_policy, :disallowed, "Password")

    assert {:error, :password_disallowed} =
             PasswordPolicy.validate(nil, "password", disallowed_password)

    assert {:error, :password_disallowed} =
             PasswordPolicy.validate(nil, "test-only-disallowed", @test_policy)

    assert :ok = PasswordPolicy.validate(nil, "a sufficiently long test", @test_policy)
  end

  test "matches Java blank, trim, and UTF-16 username-length behavior" do
    nbsp = String.duplicate("\u00A0", 8)
    em_spaces = String.duplicate("\u2003", 8)

    # Java Character.isWhitespace excludes non-breaking spaces but includes EM SPACE.
    assert :ok = PasswordPolicy.validate(nil, nbsp, @test_policy)
    assert {:error, :password_required} = PasswordPolicy.validate(nil, em_spaces, @test_policy)

    # Java String.trim does not remove NBSP, while it removes tabs at both ends.
    assert :ok = PasswordPolicy.validate("\u00A0alice\u00A0", "alice123", @test_policy)

    assert {:error, :password_contains_username} =
             PasswordPolicy.validate("\tAlice\t", "alice123", @test_policy)

    # Two supplementary code points occupy four Java UTF-16 code units.
    assert {:error, :password_contains_username} =
             PasswordPolicy.validate("😀😀", "x😀😀12345", @test_policy)

    assert :ok =
             PasswordPolicy.validate(
               nil,
               " Aa123456789 ",
               PasswordPolicy.production_defaults()
             )
  end

  test "SysUser changesets preserve password whitespace for the Native policy" do
    nbsp = String.duplicate("\u00A0", 8)
    em_spaces = String.duplicate("\u2003", 8)
    edge_spaces = " Aa123456789 "

    nbsp_changeset =
      SysUser.create_changeset(%SysUser{}, %{username: "nbsp_policy_user", password: nbsp})

    assert nbsp_changeset.valid?
    assert Bcrypt.verify_pass(nbsp, get_change(nbsp_changeset, :password))

    em_space_changeset =
      SysUser.create_changeset(%SysUser{}, %{username: "em_policy_user", password: em_spaces})

    refute em_space_changeset.valid?
    assert {"不能为空", metadata} = em_space_changeset.errors[:password]
    assert Keyword.get(metadata, :validation) == :required
    assert PasswordPolicy.error_code(em_space_changeset) == :password_required

    edge_space_changeset =
      SysUser.create_changeset(%SysUser{}, %{username: "edge_policy_user", password: edge_spaces})

    assert edge_space_changeset.valid?
    assert Bcrypt.verify_pass(edge_spaces, get_change(edge_space_changeset, :password))

    existing_user = %SysUser{
      username: "password_update_user",
      password: Bcrypt.hash_pwd_salt("old")
    }

    reset_changeset = SysUser.password_changeset(existing_user, %{password: nbsp})
    assert reset_changeset.valid?
    assert Bcrypt.verify_pass(nbsp, get_change(reset_changeset, :password))
  end

  # 变更集保留 Native 的八类密码错误和资料更新中的空白密码语义。
  test "returns dedicated codes in Native validation order" do
    strict = Map.put(PasswordPolicy.production_defaults(), :disallowed, "forbidden123!")

    cases = [
      {nil, :password_required},
      {"\t\u2003", :password_required},
      {"Short!1", :password_too_short},
      {"forbidden123!", :password_disallowed},
      {"PolicyUser42!A", :password_contains_username},
      {"lowercase123!", :password_missing_uppercase},
      {"UPPERCASE123!", :password_missing_lowercase},
      {"NoDigitsHere!!", :password_missing_digit},
      {"NoSpecial1234", :password_missing_special}
    ]

    Enum.each(cases, fn {password, expected} ->
      assert {:error, ^expected} = PasswordPolicy.validate("PolicyUser42", password, strict)
    end)
  end

  test "optional profile updates ignore missing, null and Java-blank passwords" do
    user = %SysUser{username: "optional_password_user", password: Bcrypt.hash_pwd_salt("old")}

    for attrs <- [%{}, %{password: nil}, %{password: ""}, %{password: "\t\u2003"}] do
      changeset = SysUser.update_changeset(user, attrs)
      assert changeset.valid?
      assert PasswordPolicy.error_code(changeset) == nil
      refute Map.has_key?(changeset.changes, :password)
    end

    invalid = SysUser.update_changeset(user, %{password: "test-only-disallowed"})
    refute invalid.valid?
    assert PasswordPolicy.error_code(invalid) == :password_disallowed
  end

  test "validates configured minimum boundaries and flag types" do
    at_maximum = Map.merge(@test_policy, %{min_length: 256})
    assert :ok = PasswordPolicy.validate(nil, String.duplicate("a", 256), at_maximum)

    assert_raise ArgumentError, fn ->
      PasswordPolicy.normalize_config!(Map.put(@test_policy, :min_length, 7))
    end

    assert_raise ArgumentError, fn ->
      PasswordPolicy.normalize_config!(Map.put(@test_policy, :min_length, 257))
    end

    assert_raise ArgumentError, fn ->
      PasswordPolicy.normalize_config!(Map.put(@test_policy, :require_digit, "true"))
    end
  end

  test "records bcrypt's shared 72 UTF-8 byte boundary without rejecting Native inputs" do
    policy = PasswordPolicy.production_defaults()
    prefix = "Aa1!" <> String.duplicate("x", 68)
    first = prefix <> "é"
    second = prefix <> "z"

    assert byte_size(prefix) == 72
    assert byte_size(first) > 72
    assert byte_size(second) > 72
    assert :ok = PasswordPolicy.validate(nil, first, policy)
    assert :ok = PasswordPolicy.validate(nil, second, policy)

    # 不换两端策略时，该断言明确记录 bcrypt 会忽略超过前 72 字节的尾部。
    hash = Bcrypt.hash_pwd_salt(first, log_rounds: 4)
    assert Bcrypt.verify_pass(second, hash)
  end
end
