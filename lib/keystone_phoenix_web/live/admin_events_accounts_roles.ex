defmodule KeystonePhoenixWeb.Live.AdminEvents.AccountsRoles do
  @moduledoc "处理用户表单中的角色选择，并保留停用角色的显式移除流程。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  @doc "更新表单角色草稿；未操作角色时不向保存请求提交 roleCodes。"
  def handle_event(%{"role-code" => code, "selected" => selected}, socket) do
    if role_editor_allowed?(socket) do
      toggle_role(code, selected, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event(_params, socket), do: {:noreply, socket}

  defp toggle_role(code, selected, socket) do
    roles = List.wrap(socket.assigns.role_rows)
    role = Enum.find(roles, &(role_code(&1) == code))
    selected_codes = role_codes(socket.assigns.user_form["roleCodes"])
    assigned? = code in selected_codes
    requested? = selected == "true"

    if role && may_change_role?(role, assigned?, requested?, roles, selected_codes) do
      next_codes =
        if requested?,
          do: Enum.uniq([code | selected_codes]),
          else: List.delete(selected_codes, code)

      user_form =
        socket.assigns.user_form
        |> Map.put("roleCodes", Enum.join(next_codes, ","))
        |> Map.put("roleCodesDirty", true)

      {:noreply, assign(socket, user_form: user_form)}
    else
      {:noreply, socket}
    end
  end

  defp role_editor_allowed?(socket) do
    user_form = socket.assigns[:user_form] || %{}
    user_permission = if user_form["userId"] in [nil, ""], do: "user:create", else: "user:update"

    socket.assigns[:active_modal] == "user" and
      socket.assigns[:role_scope_allowed] == true and
      is_nil(socket.assigns[:role_directory_feedback]) and
      Support.permission_socket?(socket, user_permission) and
      Support.permission_socket?(socket, "role:read") and
      Support.permission_socket?(socket, "role:assign")
  end

  # 已绑定的停用角色只能移除；移除其余停用绑定前，启用角色仍不可改动。
  defp may_change_role?(role, assigned?, requested?, roles, selected_codes) do
    cond do
      assigned? == requested? -> false
      role_enabled?(role) -> not has_selected_disabled_role?(roles, selected_codes)
      true -> assigned? and not requested?
    end
  end

  defp has_selected_disabled_role?(roles, selected_codes),
    do: Enum.any?(roles, &(not role_enabled?(&1) and role_code(&1) in selected_codes))

  defp role_enabled?(role),
    do: role["status"] in [1, "1", true] or role["enabled"] in [1, "1", true]

  defp role_code(role), do: to_string(role["roleKey"] || role["code"] || "")

  defp role_codes(codes) when is_list(codes),
    do:
      codes
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

  defp role_codes(codes) when is_binary(codes),
    do:
      codes
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

  defp role_codes(_codes), do: []
end
