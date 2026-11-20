defmodule KeystonePhoenixWeb.Live.AdminEvents.AccountsUserDeletion do
  @moduledoc "用户删除确认状态和已选用户 ID 校验。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  # 只有具备删除权限且至少选中一个用户时，服务端才打开确认框。
  def handle_event("open-user-delete", _params, socket) do
    authorized = Support.permission_socket?(socket, "user:delete")
    selected = socket.assigns.selected_user_ids != []

    next_socket =
      if authorized and selected,
        do: assign(socket, active_modal: "user-delete", user_feedback: nil),
        else: socket

    {:noreply, next_socket}
  end

  def handle_event("close-user-delete", _params, socket) do
    next_socket =
      if socket.assigns.active_modal == "user-delete",
        do: assign(socket, active_modal: nil, user_feedback: nil),
        else: socket

    {:noreply, next_socket}
  end

  # 表单只允许提交与服务端当前选择完全相同的 ID 集合。
  def confirmed_ids(params, %{assigns: %{active_modal: "user-delete"}} = socket) do
    submitted_ids = parse_ids(params["user-ids"])
    selected_ids = socket.assigns.selected_user_ids

    if submitted_ids != [] and length(submitted_ids) == length(selected_ids) and
         MapSet.new(submitted_ids) == MapSet.new(selected_ids) do
      {:ok, submitted_ids}
    else
      {:error, Feedback.error(:validation_failed, "确认删除的用户与当前选择不一致，请重新选择。")}
    end
  end

  def confirmed_ids(_params, _socket), do: :ignore

  defp parse_ids(ids) when is_binary(ids), do: String.split(ids, ",", trim: true)
  defp parse_ids(_ids), do: []
end
