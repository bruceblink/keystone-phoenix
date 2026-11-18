defmodule KeystonePhoenixWeb.Live.AdminPages.RoleDirectory do
  @moduledoc "读取用户表单使用的角色目录，并保留失败状态。"

  alias KeystonePhoenixWeb.Live.AdminPages.OrganizationData
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  # 明确区分成功的空目录和读取失败，防止失败表单误提交空角色集合。
  def load(options) when is_list(options) do
    case OrganizationData.load_roles_result(options) do
      {:ok, rows} ->
        %{rows: rows, feedback: nil}

      {:error, reason} ->
        %{rows: [], feedback: Support.read_error_feedback(reason, "角色目录读取失败，暂时不能修改用户角色。")}
    end
  end

  def empty, do: %{rows: [], feedback: nil}
end
