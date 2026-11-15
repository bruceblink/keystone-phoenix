defmodule KeystonePhoenixWeb.Live.AdminEvents.Accounts do
  @moduledoc "LiveView event handlers for the accounts domain."

  import Phoenix.LiveView, only: [consume_uploaded_entries: 3, push_event: 3]
  import Phoenix.Component, only: [assign: 2]
  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Upload
  alias KeystonePhoenix.User
  alias KeystonePhoenixWeb.Live.AdminEventsAccountsParams, as: AccountParams
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.UserController

  def handle_event("filter-users", params, socket) do
    if Support.panel_allowed?(socket, "users") do
      filters = user_filter_params(params)

      {:noreply,
       assign(socket,
         user_rows: Support.load_users_for_socket(socket, filters),
         user_query: filters["username"],
         user_display_name_query: filters["displayName"],
         selected_user_ids: [],
         page_nums: Map.put(socket.assigns.page_nums, "users", 1),
         user_feedback: nil,
         active_modal: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reset-user-filter", _params, socket),
    do: handle_event("filter-users", %{}, socket)

  def handle_event("refresh-users", _params, socket) do
    if Support.panel_allowed?(socket, "users") do
      {:noreply,
       assign(socket,
         user_rows: Support.load_users_for_socket(socket, %{}),
         page_nums: Map.put(socket.assigns.page_nums, "users", 1),
         user_query: "",
         user_display_name_query: "",
         selected_user_ids: [],
         user_form: Support.empty_user_form(),
         user_feedback: nil,
         active_modal: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("export-users", params, socket) do
    if Support.permission_socket?(socket, "user:export") do
      case UserController.export_workbook(params, principal(socket)) do
        {:ok, binary} ->
          {:noreply,
           push_event(socket, "download-xlsx", %{
             filename: "users.xlsx",
             content: Base.encode64(binary),
             content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
           })}

        {:error, _reason} ->
          {:noreply, assign(socket, user_feedback: Feedback.error("Excel 导出失败"))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-user-import", _params, socket) do
    if Support.permission_socket?(socket, "user:import") do
      {:noreply,
       assign(socket, active_modal: "user-import", user_feedback: nil, user_import_result: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "toggle-user-selection",
        %{"user-id" => user_id, "selected" => selected},
        socket
      ) do
    selected_ids = Map.get(socket.assigns, :selected_user_ids, [])

    selected_ids =
      if selected == "true",
        do: Enum.uniq([user_id | selected_ids]),
        else: List.delete(selected_ids, user_id)

    {:noreply, assign(socket, selected_user_ids: selected_ids)}
  end

  def handle_event("toggle-all-user-selection", %{"selected" => selected}, socket) do
    page_ids =
      Enum.map(
        page_rows(
          socket.assigns.user_rows,
          socket.assigns.page_nums["users"],
          socket.assigns.page_sizes["users"]
        ),
        &to_string(&1["userId"])
      )

    selected_ids = Map.get(socket.assigns, :selected_user_ids, [])

    selected_ids =
      if selected == "true",
        do: Enum.uniq(selected_ids ++ page_ids),
        else: selected_ids -- page_ids

    {:noreply, assign(socket, selected_user_ids: selected_ids)}
  end

  def handle_event("delete-users", %{"user-ids" => user_ids}, socket) do
    delete_users(socket, String.split(user_ids, ",", trim: true))
  end

  def handle_event("import-users", _params, socket) do
    cond do
      not Support.permission_socket?(socket, "user:import") ->
        {:noreply, socket}

      not mfa_step_up?(socket) ->
        discard_import_upload(socket, :mfa_required)

      true ->
        import_uploaded_users(socket)
    end
  end

  def handle_event("new-user", _params, socket) do
    if Support.permission_socket?(socket, "user:create") do
      {:noreply,
       assign(socket,
         user_form: Support.empty_user_form(),
         user_feedback: nil,
         active_modal: "user"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-user", %{"user-id" => user_id}, socket) do
    if Support.permission_socket?(socket, "user:update") do
      case Enum.find(socket.assigns.user_rows, &(to_string(&1["userId"]) == user_id)) do
        nil ->
          {:noreply, assign(socket, user_feedback: Feedback.error("找不到指定用户"))}

        user ->
          user_form =
            Support.empty_user_form()
            |> Map.merge(user)
            |> Map.put("enabled", user["status"] in [1, "1", true])
            |> Map.put("roleCodes", user["roleKey"] || "")

          {:noreply,
           assign(socket,
             user_form: user_form,
             user_feedback: nil,
             active_modal: "user"
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-user", params, socket) do
    if Support.permission_socket?(socket, "user:create") or
         Support.permission_socket?(socket, "user:update") do
      case AccountParams.normalize_user_params(params) do
        {:ok, params} ->
          user_id = String.trim(params["userId"] || "")
          params = if user_id == "", do: params, else: Map.delete(params, "password")

          result =
            cond do
              user_id == "" and
                  Authz.scope_allowed?(socket.assigns.current_user, :dept, params["deptId"]) ->
                User.create_user(params, authorization: authorization(socket, "user:create"))

              user_id != "" and
                  Authz.scope_allowed?(
                    socket.assigns.current_user,
                    :user_update,
                    user_id,
                    %{attrs: params}
                  ) ->
                User.update_user(user_id, params,
                  authorization: authorization(socket, "user:update")
                )

              true ->
                {:error, :data_scope_denied}
            end

          case result do
            {:ok, _user} ->
              {:noreply,
               assign(socket,
                 user_rows: reload_users(socket),
                 role_rows: Support.load_roles_for_socket(socket),
                 user_form: Support.empty_user_form(),
                 active_modal: nil,
                 user_feedback: if(user_id == "", do: "用户已创建", else: "用户已更新")
               )}

            {:error, :data_scope_denied} ->
              {:noreply, assign(socket, user_feedback: Feedback.error("没有数据权限"))}

            error ->
              {:noreply, assign(socket, user_feedback: Support.form_error(error))}
          end

        {:error, reason} ->
          {:noreply, assign(socket, user_feedback: Support.form_error({:error, reason}))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-user-status", %{"user-id" => user_id, "status" => status}, socket) do
    if Support.permission_socket?(socket, "user:update") do
      result =
        if Authz.scope_allowed?(socket.assigns.current_user, :user, user_id) do
          User.change_status(user_id, status, authorization: authorization(socket, "user:update"))
        else
          {:error, :data_scope_denied}
        end

      case result do
        {:ok, _user} ->
          if to_string(socket.assigns.current_user["userId"]) == user_id and status in [0, "0"] do
            {:noreply, Support.expire_authentication(socket, "当前账号已停用，请联系管理员")}
          else
            {:noreply,
             assign(socket,
               user_rows: reload_users(socket),
               user_feedback: "用户状态已更新"
             )}
          end

        {:error, :data_scope_denied} ->
          {:noreply, assign(socket, user_feedback: Feedback.error("没有数据权限"))}

        error ->
          {:noreply, assign(socket, user_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-user", %{"user-id" => user_id}, socket) do
    delete_users(socket, [user_id])
  end

  def handle_event("reset-user-password", params, socket) do
    if Support.permission_socket?(socket, "user:reset-password") do
      user_id = params["userId"] || params["user-id"]
      password = params["password"] || ""

      result =
        if Authz.scope_allowed?(socket.assigns.current_user, :user, user_id) do
          User.reset_password(user_id, %{"password" => password},
            authorization: authorization(socket, "user:reset-password")
          )
        else
          {:error, :data_scope_denied}
        end

      case result do
        {:ok, _user} ->
          if to_string(socket.assigns.current_user["userId"]) == to_string(user_id) do
            {:noreply, Support.expire_authentication(socket, "密码已重置，请重新登录")}
          else
            {:noreply, assign(socket, user_feedback: "用户密码已重置", active_modal: nil)}
          end

        {:error, :data_scope_denied} ->
          {:noreply, assign(socket, user_feedback: Feedback.error("没有数据权限"))}

        error ->
          {:noreply, assign(socket, user_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-profile", params, socket) do
    if Support.authenticated_socket?(socket) do
      user_id = socket.assigns.current_user["userId"]

      case User.update_profile(user_id, params, authorization: self_authorization(socket)) do
        {:ok, _user} ->
          case User.profile(user_id) do
            {:ok, profile} ->
              profile_user = profile["user"] || profile

              {:noreply,
               assign(socket,
                 current_user: profile_user,
                 profile_form: profile_user,
                 profile_feedback: "个人资料已保存"
               )}

            _ ->
              {:noreply, assign(socket, profile_feedback: "个人资料已保存")}
          end

        error ->
          {:noreply, assign(socket, profile_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("change-profile-password", params, socket) do
    if Support.authenticated_socket?(socket) do
      case User.update_password(
             socket.assigns.current_user["userId"],
             params,
             authorization: self_authorization(socket)
           ) do
        {:ok, _user} ->
          {:noreply, Support.expire_authentication(socket, "密码已更新，请重新登录")}

        error ->
          {:noreply, assign(socket, profile_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("update-profile-avatar", %{"avatar" => avatar}, socket) do
    if Support.authenticated_socket?(socket) do
      previous_avatar = socket.assigns.current_user["avatar"]

      case User.update_avatar(
             socket.assigns.current_user["userId"],
             avatar,
             authorization: self_authorization(socket)
           ) do
        {:ok, _user} ->
          if is_binary(previous_avatar) and previous_avatar != avatar,
            do: Upload.delete_avatar(previous_avatar)

          {:noreply,
           assign(socket,
             profile_form: Map.put(socket.assigns.profile_form, "avatar", avatar),
             profile_feedback: "头像地址已更新"
           )}

        error ->
          {:noreply, assign(socket, profile_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-profile-avatar-upload", _params, socket) do
    if Support.authenticated_socket?(socket) do
      user_id = socket.assigns.current_user["userId"]
      previous_avatar = socket.assigns.current_user["avatar"]

      results =
        consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
          upload = %Plug.Upload{
            path: path,
            filename: entry.client_name,
            content_type: entry.client_type
          }

          with {:ok, avatar_url} <- Upload.store_avatar(upload) do
            case User.update_avatar(user_id, avatar_url,
                   authorization: self_authorization(socket)
                 ) do
              {:ok, _user} ->
                if is_binary(previous_avatar) and previous_avatar != avatar_url,
                  do: Upload.delete_avatar(previous_avatar)

                {:ok, avatar_url}

              {:error, reason} ->
                Upload.delete_avatar(avatar_url)
                {:ok, {:error, reason}}
            end
          else
            {:error, reason} ->
              {:ok, {:error, reason}}
          end
        end)

      case results do
        [{:error, reason}] ->
          {:noreply, assign(socket, profile_feedback: Support.form_error({:error, reason}))}

        [avatar_url] when is_binary(avatar_url) ->
          {:noreply,
           assign(socket,
             current_user: Map.put(socket.assigns.current_user, "avatar", avatar_url),
             profile_form: Map.put(socket.assigns.profile_form, "avatar", avatar_url),
             profile_feedback: "头像已上传"
           )}

        [] ->
          {:noreply, assign(socket, profile_feedback: Feedback.error("请选择头像文件"))}
      end
    else
      {:noreply, socket}
    end
  end

  defp import_uploaded_users(socket) do
    results =
      consume_uploaded_entries(socket, :user_import, fn %{path: path}, entry ->
        upload_result = UserController.import_file(path, entry.client_name, principal(socket))
        {:ok, upload_result}
      end)

    case results do
      [{:ok, %{"total" => total, "success" => success, "failed" => failed}}] ->
        message = "用户导入完成：成功 #{success} 条，失败 #{length(failed)} 条，共 #{total} 条"

        {:noreply,
         assign(socket,
           user_rows: reload_users(socket),
           user_feedback: message,
           user_import_result: %{"total" => total, "success" => success, "failed" => failed},
           active_modal: "user-import"
         )}

      [{:error, reason}] ->
        {:noreply, assign(socket, user_feedback: Feedback.error(import_error_message(reason)))}

      [] ->
        {:noreply, assign(socket, user_feedback: Feedback.error("请选择用户导入文件"))}
    end
  end

  defp discard_import_upload(socket, reason) do
    results =
      consume_uploaded_entries(socket, :user_import, fn _meta, _entry ->
        {:ok, {:error, reason}}
      end)

    case results do
      [] ->
        {:noreply, assign(socket, user_feedback: Feedback.error(import_error_message(reason)))}

      [{:error, ^reason}] ->
        {:noreply, assign(socket, user_feedback: Feedback.error(import_error_message(reason)))}

      _ ->
        {:noreply, assign(socket, user_feedback: Feedback.error(import_error_message(reason)))}
    end
  end

  defp mfa_step_up?(socket) do
    case Auth.session_context(socket.assigns[:access_token]) do
      {:ok, %{authentication_level: "AAL2"}} -> true
      _ -> false
    end
  end

  defp import_error_message(:mfa_required), do: "导入用户需要完成二次认证"
  defp import_error_message(:invalid_headers), do: "Excel 表头无效"
  defp import_error_message(:empty_sheet), do: "Excel 工作表为空"
  defp import_error_message(:invalid_workbook), do: "Excel 文件无效或超过大小限制"
  defp import_error_message(reason), do: Support.human_error(reason)

  defp principal(socket) do
    Map.put(socket.assigns.current_user, :permissions, List.wrap(socket.assigns[:permissions]))
  end

  defp authorization(socket, permission) do
    principal =
      Map.put(
        socket.assigns.current_user,
        :permissions,
        List.wrap(socket.assigns[:permissions])
      )

    %{principal: principal, permission: permission}
  end

  defp self_authorization(socket) do
    principal =
      Map.put(
        socket.assigns.current_user,
        :permissions,
        List.wrap(socket.assigns[:permissions])
      )

    %{principal: principal}
  end

  # 过滤条件只在事件入口清理一次，内部查询使用已确定的字符串值。
  defp user_filter_params(params) do
    %{
      "username" => String.trim(to_string(params["username"] || "")),
      "displayName" => String.trim(to_string(params["displayName"] || ""))
    }
  end

  defp current_user_filters(socket) do
    user_filter_params(%{
      "username" => socket.assigns[:user_query],
      "displayName" => socket.assigns[:user_display_name_query]
    })
  end

  defp reload_users(socket),
    do: Support.load_users_for_socket(socket, current_user_filters(socket))

  defp page_rows(rows, page_num, page_size) do
    rows
    |> Enum.drop(max(page_num - 1, 0) * page_size)
    |> Enum.take(page_size)
  end

  defp delete_users(socket, user_ids) do
    if Support.permission_socket?(socket, "user:delete") do
      case if(Authz.scope_allowed?(socket.assigns.current_user, :users, user_ids),
             do:
               User.delete_users(user_ids,
                 authorization: authorization(socket, "user:delete")
               ),
             else: {:error, :data_scope_denied}
           ) do
        :ok ->
          {:noreply,
           assign(socket,
             user_rows: reload_users(socket),
             role_rows: Support.load_roles_for_socket(socket),
             user_form: Support.empty_user_form(),
             active_modal: nil,
             selected_user_ids: [],
             user_feedback: "已删除 #{length(user_ids)} 个用户"
           )}

        {:error, :data_scope_denied} ->
          {:noreply, assign(socket, user_feedback: Feedback.error("没有数据权限"))}

        error ->
          {:noreply, assign(socket, user_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end
end
