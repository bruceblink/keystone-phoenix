defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationExport do
  @moduledoc "组织页面的岗位和角色 Excel 导出事件。"

  import Phoenix.LiveView, only: [push_event: 3]
  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Post
  alias KeystonePhoenix.Role
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def handle_event("export-posts", _params, socket) do
    export_rows(
      socket,
      "post:export",
      :post_feedback,
      "posts.xlsx",
      [
        "岗位ID",
        "岗位编码",
        "岗位名称",
        "岗位排序",
        "备注",
        "状态",
        "创建时间"
      ],
      fn row ->
        [
          row["postId"],
          row["postCode"],
          row["postName"],
          row["postSort"],
          row["remark"],
          status_label(row["status"]),
          row["createTime"]
        ]
      end,
      &Post.list_posts_for_export/2
    )
  end

  def handle_event("export-roles", _params, socket) do
    export_rows(
      socket,
      "role:export",
      :role_feedback,
      "roles.xlsx",
      [
        "角色ID",
        "角色名称",
        "角色标识",
        "角色排序",
        "角色状态",
        "备注",
        "创建时间",
        "数据范围"
      ],
      fn row ->
        [
          row["roleId"],
          row["roleName"],
          row["roleKey"],
          row["roleSort"],
          status_label(row["status"]),
          row["remark"],
          row["createTime"],
          row["dataScope"]
        ]
      end,
      &Role.list_roles_for_export/2
    )
  end

  defp export_rows(socket, permission, feedback_key, filename, headers, row_mapper, fetcher) do
    if Support.permission_socket?(socket, permission) do
      authorization = authorization(socket, permission)

      case Excel.all_rows_result(fn params -> fetcher.(params, authorization) end) do
        {:ok, rows} ->
          case Excel.export(headers, Enum.map(rows, row_mapper), filename) do
            {:ok, binary} ->
              {:noreply,
               push_event(socket, "download-xlsx", %{
                 filename: filename,
                 content: Base.encode64(binary),
                 content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
               })}

            {:error, _reason} ->
              export_error(socket, feedback_key)
          end

        {:error, _reason} ->
          export_error(socket, feedback_key)
      end
    else
      {:noreply, socket}
    end
  end

  defp export_error(socket, feedback_key),
    do: {:noreply, assign(socket, [{feedback_key, Feedback.error("Excel 导出失败")}])}

  defp authorization(socket, permission) do
    principal =
      socket.assigns.current_user
      |> Map.put(:permissions, List.wrap(socket.assigns[:permissions]))

    [authorization: %{principal: principal, permission: permission}]
  end

  defp status_label(1), do: "正常"
  defp status_label(0), do: "停用"
  defp status_label(status), do: to_string(status || "")
end
