defmodule KeystonePhoenix.Notification do
  @moduledoc "Private user inbox queries and API Key lifecycle notification writes."

  import Ecto.Query
  require Logger

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Notification.SysNotification
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Repo

  @inbox_limit 50

  @api_key_events %{
    created: {"api_key.created", "API Key 已签发", "一个 API Key 已成功签发。"},
    rotated: {"api_key.rotated", "API Key 已轮换", "一个 API Key 已轮换，旧密钥已失效。"},
    revoked: {"api_key.revoked", "API Key 已撤销", "一个 API Key 已撤销。"}
  }

  @doc "读取当前用户最近 50 条通知，并统计该用户全部未读通知。"
  def list_for_user(user_id), do: list_for_user_page(user_id, 1, false)

  @doc "读取当前用户指定页的通知，使用 has_more 指示是否存在下一页。"
  def list_for_user(user_id, page) when is_integer(page) and page in 1..1_000_000,
    do: list_for_user_page(user_id, page, true)

  def list_for_user(_user_id, _page), do: {:error, :invalid_page}

  defp list_for_user_page(user_id, page, paged?) do
    with {:ok, user_id} <- Params.parse_uuid(user_id) do
      items =
        Repo.all(
          from notification in SysNotification,
            where: notification.user_id == ^user_id,
            order_by: [desc: notification.created_at, desc: notification.id],
            offset: ^((page - 1) * @inbox_limit),
            limit: ^(@inbox_limit + if(paged?, do: 1, else: 0))
        )

      unread_count =
        Repo.aggregate(
          from(notification in SysNotification,
            where: notification.user_id == ^user_id and is_nil(notification.read_at)
          ),
          :count,
          :id
        )

      inbox = %{
        items: items |> Enum.take(@inbox_limit) |> Enum.map(&to_map/1),
        unread_count: unread_count
      }

      # 未传 page 的旧接口保留原有响应字段；显式分页多读一条判断下一页。
      if paged?,
        do: {:ok, Map.merge(inbox, %{page: page, has_more: length(items) > @inbox_limit})},
        else: {:ok, inbox}
    else
      :error -> {:error, :not_found}
    end
  rescue
    error ->
      log_query_failure(:list, error)
      {:error, :service_unavailable}
  end

  @doc "统计当前用户全部未读通知，不读取通知正文。"
  def unread_count_for_user(user_id) do
    with {:ok, user_id} <- Params.parse_uuid(user_id) do
      unread_count =
        Repo.aggregate(
          from(notification in SysNotification,
            where: notification.user_id == ^user_id and is_nil(notification.read_at)
          ),
          :count,
          :id
        )

      {:ok, unread_count}
    else
      :error -> {:error, :not_found}
    end
  rescue
    error ->
      log_query_failure(:unread_count, error)
      {:error, :service_unavailable}
  end

  @doc "按用户 ID 读取通知；未知 ID 和其他用户的 ID 返回相同结果。"
  def get_for_user(user_id, notification_id) do
    with {:ok, user_id} <- Params.parse_uuid(user_id),
         {:ok, notification_id} <- Params.parse_uuid(notification_id),
         %SysNotification{} = notification <- find(user_id, notification_id) do
      {:ok, to_map(notification)}
    else
      _ -> {:error, :not_found}
    end
  rescue
    error ->
      log_query_failure(:get, error)
      {:error, :service_unavailable}
  end

  @doc "将当前用户的通知标记为已读；重复调用保留首次 read_at。"
  def mark_read(user_id, notification_id) do
    with {:ok, user_id} <- Params.parse_uuid(user_id),
         {:ok, notification_id} <- Params.parse_uuid(notification_id) do
      query =
        from notification in SysNotification,
          where: notification.user_id == ^user_id and notification.id == ^notification_id

      Repo.update_all(
        from(notification in query, where: is_nil(notification.read_at)),
        set: [read_at: DateTime.utc_now()]
      )

      read_existing(query)
    else
      _ -> {:error, :not_found}
    end
  rescue
    error ->
      log_query_failure(:read, error)
      {:error, :service_unavailable}
  end

  @doc "在 API Key 所属用户的现有业务事务中新增生命周期通知。"
  def create_api_key_event!(user_id, event) when is_binary(user_id) do
    {type, title, content} = Map.fetch!(@api_key_events, event)

    %SysNotification{}
    |> SysNotification.changeset(%{
      id: Identity.v7(),
      user_id: user_id,
      type: type,
      title: title,
      content: content,
      created_at: DateTime.utc_now()
    })
    |> Repo.insert!()
  end

  @doc "映射为通知 HTTP 响应字段。"
  def to_map(%SysNotification{} = notification) do
    %{
      "id" => notification.id,
      "type" => notification.type,
      "title" => notification.title,
      "content" => notification.content,
      "createdAt" => DateTime.to_iso8601(notification.created_at),
      "readAt" => format_datetime(notification.read_at)
    }
  end

  defp find(user_id, notification_id) do
    Repo.one(
      from notification in SysNotification,
        where: notification.user_id == ^user_id and notification.id == ^notification_id
    )
  end

  defp read_existing(query) do
    case Repo.one(query) do
      %SysNotification{} = notification -> {:ok, to_map(notification)}
      nil -> {:error, :not_found}
    end
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(datetime), do: DateTime.to_iso8601(datetime)

  defp log_query_failure(operation, error) do
    Logger.error(
      "notification operation=#{operation} failed exception=#{inspect(error.__struct__)}"
    )
  end
end
