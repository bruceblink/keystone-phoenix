defmodule KeystonePhoenixWeb.UserImportFailure do
  @moduledoc """
  将用户导入的单行失败转换为接口明细。

  该模块只负责失败原因和稳定错误码映射，不会改变导入事务、逐行结果或 HTTP 状态。
  """

  alias KeystonePhoenix.User.PasswordPolicy

  @doc "把单行失败转换为接口使用的行号、用户名、原因和业务错误码。"
  def to_map(row_number, record, reason) do
    %{
      "row" => row_number,
      "username" => Map.get(record, "username", ""),
      "reason" => failure_reason(reason),
      "code" => failure_code(reason)
    }
  end

  defp failure_code(%Ecto.Changeset{} = changeset) do
    cond do
      username_already_exists?(changeset) -> "username_already_exists"
      true -> password_or_generic_failure_code(changeset)
    end
  end

  defp failure_code(:data_scope_denied), do: "data_scope_denied"
  defp failure_code(:role_assignment_forbidden), do: "permission_denied"
  defp failure_code(:not_found), do: "resource_not_found"
  defp failure_code(:unavailable), do: "service_unavailable"
  defp failure_code(_reason), do: "validation_failed"

  defp password_or_generic_failure_code(changeset) do
    case PasswordPolicy.error_code(changeset) do
      nil ->
        if username_invalid_format?(changeset),
          do: "username_invalid_format",
          else: "validation_failed"

      code ->
        Atom.to_string(code)
    end
  end

  defp failure_reason(%Ecto.Changeset{} = changeset) do
    if username_already_exists?(changeset) do
      "username already exists"
    else
      changeset
      |> Ecto.Changeset.traverse_errors(&format_validation_message/1)
      |> Enum.flat_map(fn {field, messages} ->
        Enum.map(List.wrap(messages), &"#{field_name(field)}：#{&1}")
      end)
      |> Enum.join("；")
      |> case do
        "" -> "用户数据无效"
        message -> message
      end
    end
  end

  defp failure_reason(:data_scope_denied), do: "没有数据权限"
  defp failure_reason(:role_assignment_forbidden), do: "没有角色分配权限"
  defp failure_reason(reason), do: to_string(reason)

  # 只根据唯一约束元数据识别重复用户名，不依赖可读错误文本。
  defp username_already_exists?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:username, {_message, opts}} ->
        Keyword.get(opts, :constraint) == :unique and
          Keyword.get(opts, :constraint_name) == "sys_user_username_unique_index"

      _error ->
        false
    end)
  end

  # 只映射用户名字段原有的正则校验；其他输入规则保持原有分类。
  defp username_invalid_format?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:username, {_message, opts}} -> Keyword.get(opts, :validation) == :format
      _error -> false
    end)
  end

  # 展开 Changeset 的长度等参数，保留原有可读原因格式。
  defp format_validation_message({message, opts}) do
    Regex.replace(~r"%{(\w+)}", message, fn _, key ->
      case Enum.find(opts, fn {option, _value} -> Atom.to_string(option) == key end) do
        {_option, value} -> to_string(value)
        nil -> "%{#{key}}"
      end
    end)
  end

  # 使用稳定的中文字段名定位失败输入。
  defp field_name(:username), do: "用户名"
  defp field_name(:nickname), do: "昵称"
  defp field_name(:password), do: "密码"
  defp field_name(:email), do: "邮箱"
  defp field_name(:phone_number), do: "联系电话"
  defp field_name(:sex), do: "性别"
  defp field_name(:status), do: "状态"
  defp field_name(:avatar), do: "头像"
  defp field_name(:remark), do: "备注"
  defp field_name(field), do: Atom.to_string(field)
end
