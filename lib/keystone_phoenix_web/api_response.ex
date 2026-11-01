defmodule KeystonePhoenixWeb.ApiResponse do
  @moduledoc """
  Shared response envelope compatible with Keystone's existing API contract.
  """

  @success_code 0
  @success_message "操作成功"

  @spec ok(term()) :: map()
  def ok(data \\ nil) do
    %{code: @success_code, msg: @success_message, data: data}
  end

  @spec error(integer(), String.t(), term()) :: map()
  def error(code, message, data \\ nil) do
    %{code: code, msg: message, data: data}
  end
end
