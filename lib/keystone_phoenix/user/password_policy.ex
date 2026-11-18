defmodule KeystonePhoenix.User.PasswordPolicy do
  @moduledoc """
  用户设置密码时统一应用 Native 的密码策略。

  策略按 Unicode code point 计数。登录仍只验证已存 bcrypt 哈希，不重新检查当前策略。
  """

  import Ecto.Changeset

  @production_defaults %{
    min_length: 12,
    require_uppercase: true,
    require_lowercase: true,
    require_digit: true,
    require_special: true,
    disallowed: "password,password1,1234567890,qwerty123,admin"
  }

  @uppercase ~r/\p{Uppercase}/u
  @lowercase ~r/\p{Lowercase}/u
  @digit ~r/\p{Nd}/u
  @letter_or_digit ~r/[\p{L}\p{Nd}]/u

  @doc "返回与 Native 生产配置相同的默认值，供配置和边界测试使用。"
  def production_defaults, do: @production_defaults

  @doc "读取并校验本进程当前的密码策略配置。"
  def current_config do
    Application.get_env(:keystone_phoenix, :password_policy, @production_defaults)
    |> normalize_config!()
  end

  @doc "把密码策略错误加入用户 changeset；错误内容不返回密码或命中规则。"
  def validate_changeset(changeset) do
    case Map.fetch(changeset.changes, :password) do
      {:ok, password} when is_binary(password) ->
        case validate(get_field(changeset, :username), password) do
          :ok -> changeset
          {:error, code} -> add_policy_error(changeset, code)
        end

      {:ok, _password} ->
        add_required_error(changeset)

      :error ->
        add_required_error(changeset)
    end
  end

  @doc "可选密码仅在非空白输入时执行策略，供用户资料更新沿用 Native 行为。"
  def validate_optional_changeset(changeset) do
    case Map.fetch(changeset.changes, :password) do
      {:ok, password} when is_binary(password) ->
        if blank?(password), do: changeset, else: validate_changeset(changeset)

      _ ->
        changeset
    end
  end

  @doc "返回当前变更集中的专用密码策略代码；其他字段错误返回 nil。"
  def error_code(%Ecto.Changeset{errors: errors}) do
    case Keyword.get(errors, :password) do
      {_message, options} -> Keyword.get(options, :password_policy_code)
      _ -> nil
    end
  end

  def error_code(_changeset), do: nil

  @doc "按 Java String.isBlank 规则判断缺失或空白密码。"
  def blank?(value) when is_binary(value), do: java_blank?(value)
  def blank?(_value), do: true

  @doc "按指定规则检查用户名与密码；调用方可以传入生产或测试配置。"
  def validate(username, password, config \\ nil) do
    config = normalize_config!(config || current_config())

    case policy_error(username, password, config) do
      nil -> :ok
      code -> {:error, code}
    end
  end

  @doc "校验配置类型和 Native 约定的最小长度边界。"
  def normalize_config!(config) when is_map(config) do
    config = Map.merge(@production_defaults, config)
    min_length = Map.fetch!(config, :min_length)

    unless is_integer(min_length) and min_length in 8..256 do
      raise ArgumentError, "password policy min_length must be between 8 and 256"
    end

    for key <- [:require_uppercase, :require_lowercase, :require_digit, :require_special] do
      unless is_boolean(Map.fetch!(config, key)) do
        raise ArgumentError, "password policy category flags must be booleans"
      end
    end

    unless is_binary(Map.fetch!(config, :disallowed)) do
      raise ArgumentError, "password policy disallowed must be a comma-separated string"
    end

    config
  end

  def normalize_config!(_config),
    do: raise(ArgumentError, "password policy configuration must be a map")

  defp add_required_error(changeset) do
    if Keyword.has_key?(changeset.errors, :password) do
      changeset
    else
      add_error(changeset, :password, "不能为空",
        validation: :required,
        password_policy_code: :password_required
      )
    end
  end

  defp add_policy_error(changeset, :password_required), do: add_required_error(changeset)

  defp add_policy_error(changeset, code) do
    add_error(changeset, :password, "密码不符合安全策略", password_policy_code: code)
  end

  # 按 Native 的短路顺序返回首个失败条件，保持同一密码只对应一个业务码。
  defp policy_error(username, password, config) when is_binary(password) do
    codepoints = String.to_charlist(password)
    lower_password = String.downcase(password)

    cond do
      java_blank?(codepoints) ->
        :password_required

      length(codepoints) < config.min_length ->
        :password_too_short

      disallowed?(lower_password, config.disallowed) ->
        :password_disallowed

      contains_username?(username, lower_password) ->
        :password_contains_username

      not category_required?(codepoints, @uppercase, config.require_uppercase) ->
        :password_missing_uppercase

      not category_required?(codepoints, @lowercase, config.require_lowercase) ->
        :password_missing_lowercase

      not category_required?(codepoints, @digit, config.require_digit) ->
        :password_missing_digit

      not special_character_required?(codepoints, config.require_special) ->
        :password_missing_special

      true ->
        nil
    end
  end

  defp policy_error(_username, _password, _config), do: :password_required

  defp disallowed?(lower_password, configured_values) do
    configured_values
    |> String.split(",")
    |> Enum.map(&java_trim/1)
    |> Enum.reject(&java_blank?/1)
    |> Enum.map(&String.downcase/1)
    |> MapSet.new()
    |> MapSet.member?(lower_password)
  end

  defp contains_username?(username, lower_password) when is_binary(username) do
    if java_blank?(username) do
      false
    else
      lower_username = username |> java_trim() |> String.downcase()

      java_utf16_length(lower_username) >= 4 and
        String.contains?(lower_password, lower_username)
    end
  end

  defp contains_username?(_username, _lower_password), do: false

  defp category_required?(_codepoints, _pattern, false), do: true

  defp category_required?(codepoints, pattern, true),
    do: Enum.any?(codepoints, &matches?(pattern, &1))

  # Java Character.isLetterOrDigit 是字母类别或十进制数字；空格、组合符和其他数字类别均算特殊字符。
  defp special_character_required?(_codepoints, false), do: true

  defp special_character_required?(codepoints, true),
    do: Enum.any?(codepoints, &(not matches?(@letter_or_digit, &1)))

  defp matches?(pattern, codepoint), do: Regex.match?(pattern, <<codepoint::utf8>>)

  # Java String.isBlank 使用 Character.isWhitespace，且不把不换行空格视为空白。
  defp java_blank?(value) when is_binary(value),
    do: value |> String.to_charlist() |> java_blank?()

  defp java_blank?(codepoints) when is_list(codepoints),
    do: codepoints == [] or Enum.all?(codepoints, &java_whitespace?/1)

  defp java_whitespace?(codepoint)
       when codepoint in 0x09..0x0D or codepoint in 0x1C..0x1F,
       do: true

  defp java_whitespace?(codepoint) when codepoint in [0x00A0, 0x2007, 0x202F], do: false

  defp java_whitespace?(codepoint)
       when codepoint in [0x0020, 0x1680, 0x2028, 0x2029, 0x205F, 0x3000] or
              codepoint in 0x2000..0x200A,
       do: true

  defp java_whitespace?(_codepoint), do: false

  # Java String.trim 只移除 U+0000 至 U+0020，与 Unicode 空白裁剪不同。
  defp java_trim(value) do
    value
    |> String.to_charlist()
    |> Enum.drop_while(&(&1 <= 0x20))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 <= 0x20))
    |> Enum.reverse()
    |> List.to_string()
  end

  # Native 的用户名长度使用 Java UTF-16 code unit 数；用户名字段原有验证保持不变。
  defp java_utf16_length(value) do
    value
    |> String.to_charlist()
    |> Enum.reduce(0, fn codepoint, count -> count + if(codepoint > 0xFFFF, do: 2, else: 1) end)
  end
end
