defmodule KeystonePhoenixWeb.ApiResponse do
  @moduledoc """
  统一 HTTP 响应封装。

  成功和失败都返回 `success`、`data`、`message`、`error` 四个字段。
  `error.code` 只使用跨项目约定的错误分类，不把内部数字错误码暴露给客户端。
  """

  @error_codes ~w(
    invalid_credential
    permission_denied
    data_scope_denied
    session_revoked
    authorization_unavailable
    validation_failed
  )

  @spec ok(term()) :: map()
  def ok(data \\ nil) do
    %{success: true, data: data, message: "OK", error: nil}
  end

  @spec error(atom() | String.t(), String.t(), term()) :: map()
  def error(code, message, data \\ nil) when is_atom(code) or is_binary(code) do
    normalized = normalize_code(code)

    if normalized in @error_codes do
      %{success: false, data: data, message: message, error: %{code: normalized}}
    else
      raise ArgumentError, "unsupported API error code: #{normalized}"
    end
  end

  defp normalize_code(code) when is_atom(code), do: Atom.to_string(code)
  defp normalize_code(code), do: String.trim(code)

  @doc "返回跨项目约定的错误分类。"
  def error_codes, do: @error_codes

  @doc "检查错误分类是否已登记。"
  def valid_error_code?(code), do: normalize_code(code) in @error_codes
end
