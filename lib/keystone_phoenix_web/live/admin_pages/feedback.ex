defmodule KeystonePhoenixWeb.Live.AdminPages.Feedback do
  @moduledoc """
  管理后台反馈信息的级别和无障碍语义。

  普通字符串表示成功或提示信息，`{:error, code, message}` 表示需要警示用户的失败反馈。
  code 使用跨项目错误码目录中的稳定标识，message 只负责页面展示。
  """

  alias KeystonePhoenixWeb.ErrorCatalog

  # 服务端失败统一保留错误级别和稳定代码，避免错误信息使用成功样式。
  def error(message) when is_binary(message), do: error(:internal_error, message)

  def error(code, message) when is_binary(message) do
    {:error, normalize_code(code), message}
  end

  def from_reason(reason), do: error(code_for_reason(reason), message_for_reason(reason))

  # 角色删除需要区分成员阻止和系统管理员保护；其他页面继续使用通用映射。
  def role_delete_error(:has_users),
    do: error(:role_has_members, "角色存在用户，不能删除")

  def role_delete_error(:protected_role),
    do: error(:role_protected, "管理员角色不能删除")

  def import_error(:mfa_required), do: error(:mfa_state_conflict, "导入用户需要完成二次认证")
  def import_error(reason), do: error(:validation_failed, import_error_message(reason))

  def message({:error, _code, message}), do: message
  def message({:error, message}), do: message
  def message(message) when is_binary(message), do: message
  def message(other), do: inspect(other)
  def code({:error, code, _message}), do: code
  def code({:error, _message}), do: "internal_error"
  def code(_feedback), do: nil
  def class({:error, _code, _message}), do: "feedback feedback--error"
  def class({:error, _message}), do: "feedback feedback--error"
  def class(_feedback), do: "feedback"
  def role({:error, _code, _message}), do: "alert"
  def role({:error, _message}), do: "alert"
  def role(_feedback), do: "status"
  def live({:error, _code, _message}), do: "assertive"
  def live({:error, _message}), do: "assertive"
  def live(_feedback), do: "polite"

  def human_error(reason), do: message(from_reason(reason))

  defp normalize_code(code) do
    if ErrorCatalog.valid?(code), do: normalize_code_value(code), else: :internal_error
  end

  defp normalize_code_value(code) when is_atom(code), do: Atom.to_string(code)
  defp normalize_code_value(code), do: code

  defp code_for_reason(reason)
       when reason in [:not_found, :menu_not_found, :parent_not_found],
       do: :resource_not_found

  defp code_for_reason(reason)
       when reason in [
              :has_users,
              :has_children,
              :has_data,
              :protected_role,
              :protected_user,
              :update_failed,
              :role_unavailable
            ],
       do: :resource_conflict

  defp code_for_reason(reason)
       when reason in [:permission_denied],
       do: :permission_denied

  defp code_for_reason(reason)
       when reason in [:data_scope_denied],
       do: :data_scope_denied

  defp code_for_reason(reason)
       when reason in [
              :unavailable,
              :service_unavailable,
              :storage_error,
              :login_limiter_unavailable
            ],
       do: :service_unavailable

  defp code_for_reason(reason)
       when reason in [:mfa_not_enrolled, :mfa_enrollment_required],
       do: :mfa_state_conflict

  defp code_for_reason(:already_logged_in), do: :active_session_conflict
  defp code_for_reason(:scope_exceeds_permissions), do: :permission_denied
  defp code_for_reason(:api_key_name_invalid), do: :api_key_name_invalid
  defp code_for_reason(:profile_avatar_required), do: :profile_avatar_required
  defp code_for_reason(:api_key_expiry_invalid), do: :api_key_expiry_invalid
  defp code_for_reason(:api_key_expiry_out_of_range), do: :api_key_expiry_out_of_range

  defp code_for_reason(reason)
       when reason in [
              :invalid_ids,
              :invalid_id,
              :invalid_parent,
              :invalid_params,
              :invalid_status,
              :invalid_log,
              :invalid_upload,
              :empty_upload,
              :file_too_large,
              :filename_too_long,
              :type_not_allowed,
              :role_codes_unsupported
            ],
       do: :validation_failed

  defp code_for_reason(_reason), do: :internal_error

  defp message_for_reason(:not_found), do: "记录不存在"
  defp message_for_reason(:invalid_ids), do: "编号无效"
  defp message_for_reason(:invalid_id), do: "编号无效"
  defp message_for_reason(:has_users), do: "记录仍被用户使用"
  defp message_for_reason(:has_children), do: "记录仍有下级数据"
  defp message_for_reason(:parent_not_found), do: "上级记录不存在"
  defp message_for_reason(:invalid_parent), do: "上级记录无效"
  defp message_for_reason(:protected_role), do: "管理员角色不能删除"
  defp message_for_reason(:protected_user), do: "当前用户或管理员不能删除"
  defp message_for_reason(:update_failed), do: "更新失败"
  defp message_for_reason(:has_data), do: "字典类型仍有数据"
  defp message_for_reason(:invalid_params), do: "参数无效"
  defp message_for_reason(:invalid_status), do: "状态无效"
  defp message_for_reason(:role_unavailable), do: "角色已停用"
  defp message_for_reason(:menu_not_found), do: "菜单不存在"
  defp message_for_reason(:invalid_log), do: "日志参数无效"
  defp message_for_reason(:unavailable), do: "服务暂不可用"
  defp message_for_reason(:invalid_upload), do: "头像文件无效"
  defp message_for_reason(:empty_upload), do: "头像文件不能为空"
  defp message_for_reason(:file_too_large), do: "头像文件不能超过 50 MB"
  defp message_for_reason(:filename_too_long), do: "头像文件名过长"
  defp message_for_reason(:type_not_allowed), do: "头像文件类型不支持"
  defp message_for_reason(:storage_error), do: "头像文件保存失败"
  defp message_for_reason(:permission_denied), do: "没有操作权限"
  defp message_for_reason(:data_scope_denied), do: "没有数据权限"
  defp message_for_reason(:already_logged_in), do: "该账号已经登录"
  defp message_for_reason(:login_limiter_unavailable), do: "登录限流服务暂不可用"
  defp message_for_reason(:scope_exceeds_permissions), do: "授权范围超过当前账号权限"
  defp message_for_reason(:api_key_name_invalid), do: "API Key 名称必须为 1 到 128 个字符。"
  defp message_for_reason(:profile_avatar_required), do: "请输入头像地址。"
  defp message_for_reason(:api_key_expiry_invalid), do: "API Key 到期时间格式无效，请重新选择时间。"

  defp message_for_reason(:api_key_expiry_out_of_range),
    do: "API Key 到期时间必须晚于当前时间且不超过 90 天。"

  defp message_for_reason(:role_codes_unsupported), do: "角色编码不受支持"
  defp message_for_reason(:mfa_not_enrolled), do: "MFA 状态不满足当前操作"
  defp message_for_reason(:mfa_enrollment_required), do: "MFA 状态不满足当前操作"
  defp message_for_reason(_reason), do: "操作失败"

  defp import_error_message(:invalid_headers), do: "Excel 表头无效"
  defp import_error_message(:empty_sheet), do: "Excel 工作表为空"
  defp import_error_message(:invalid_workbook), do: "Excel 文件无效或超过大小限制"
  defp import_error_message(_reason), do: "Excel 文件导入失败"
end
