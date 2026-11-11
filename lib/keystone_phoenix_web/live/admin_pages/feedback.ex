defmodule KeystonePhoenixWeb.Live.AdminPages.Feedback do
  @moduledoc """
  管理后台反馈信息的级别和无障碍语义。

  普通字符串表示成功或提示信息，`{:error, message}` 表示需要警示用户的失败反馈。
  """

  # 服务端失败统一保留错误级别，避免错误信息使用成功样式。
  def error(message), do: {:error, message}
  def message({:error, message}), do: message
  def message(message) when is_binary(message), do: message
  def message(other), do: inspect(other)
  def class({:error, _message}), do: "feedback feedback--error"
  def class(_feedback), do: "feedback"
  def role({:error, _message}), do: "alert"
  def role(_feedback), do: "status"
  def live({:error, _message}), do: "assertive"
  def live(_feedback), do: "polite"
end
