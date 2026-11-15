defmodule KeystonePhoenixWeb.ApiResponse do
  @moduledoc """
  统一 HTTP 响应封装。

  成功和失败都返回 `success`、`data`、`message`、`error` 四个字段。
  `error.code` 只使用跨项目约定的错误分类，不把内部数字错误码暴露给客户端。
  """

  alias KeystonePhoenixWeb.ErrorCatalog

  @spec ok(term()) :: map()
  def ok(data \\ nil) do
    %{success: true, data: data, message: "OK", error: nil}
  end

  @spec error(atom() | String.t(), String.t(), term()) :: map()
  def error(code, message, data \\ nil) when is_atom(code) or is_binary(code) do
    normalized = normalize_code(code)

    if ErrorCatalog.valid?(normalized) do
      %{success: false, data: data, message: message, error: %{code: normalized}}
    else
      raise ArgumentError, "unsupported API error code: #{normalized}"
    end
  end

  defp normalize_code(code) when is_atom(code), do: Atom.to_string(code)
  defp normalize_code(code), do: String.trim(code)

  @doc "返回跨项目约定的业务错误码。"
  def error_codes, do: ErrorCatalog.codes()

  @doc "检查错误分类是否已登记。"
  def valid_error_code?(code), do: ErrorCatalog.valid?(code)

  @doc "返回错误码的排错元数据。"
  def error_metadata(code), do: ErrorCatalog.metadata(code)

  @doc "按错误码反查包含代码和业务条件的完整目录项。"
  def error_lookup(code), do: ErrorCatalog.lookup(code)
end
