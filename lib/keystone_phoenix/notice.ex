defmodule KeystonePhoenix.Notice do
  @moduledoc "Query and command boundary for system notices."

  import Ecto.Query

  alias KeystonePhoenix.Audit
  alias KeystonePhoenix.Authz.Command
  alias KeystonePhoenix.Notice.Authorization
  alias KeystonePhoenix.Notice.SysNotice
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Pagination
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User

  @attrs [
    {"title", :notice_title},
    {"noticeTitle", :notice_title},
    {"content", :notice_content},
    {"noticeType", :notice_type},
    {"noticeContent", :notice_content},
    {"enabled", :status},
    {"status", :status},
    {"remark", :remark}
  ]

  def list_notices(params \\ %{}) do
    query =
      from(n in SysNotice,
        where: n.deleted == false,
        order_by: [desc: n.notice_id]
      )

    query = filter_contains(query, :notice_title, params["noticeTitle"] || params[:notice_title])
    query = filter_integer(query, :notice_type, params["noticeType"] || params[:notice_type])
    query = filter_integer(query, :status, params["status"] || params[:status])
    paged = Pagination.page_rows(query, params, :notice_id)
    creator_names = creator_names(paged.rows)
    %{paged | rows: Enum.map(paged.rows, &notice_to_map(&1, creator_names))}
  end

  @doc "Returns only published and enabled notices for the public Native endpoint."
  def list_public_notices do
    now = DateTime.utc_now()

    from(n in SysNotice,
      where:
        n.deleted == false and n.status == 1 and n.published == true and
          (is_nil(n.publish_at) or n.publish_at <= ^now),
      order_by: [desc: fragment("coalesce(?, ?)", n.publish_at, n.create_time), desc: n.notice_id]
    )
    |> Repo.all()
    |> native_notice_rows()
  end

  @doc "Returns all notices in the authenticated scope using the Native DTO."
  def list_managed_notices(params, options) when is_map(params) and is_list(options) do
    with {:ok, scope} <- Authorization.authorize_owner(options, "notice:read") do
      query =
        from(n in SysNotice,
          where: n.deleted == false,
          order_by: [desc: n.notice_id]
        )
        |> owner_filter(scope)
        |> filter_contains(
          :notice_title,
          params["title"] || params[:title] || params["noticeTitle"]
        )
        |> filter_integer(:notice_type, params["noticeType"] || params[:notice_type])

      {:ok, query |> Repo.all() |> native_notice_rows()}
    end
  end

  @doc "在检查公告权限和资源范围后查询公告列表。"
  def list_notices(params, options) when is_map(params) and is_list(options) do
    with {:ok, scope} <- Authorization.authorize_owner(options, "notice:read") do
      {:ok, list_notices_scoped(params, scope)}
    end
  end

  def get_notice(id) do
    case Params.parse_uuid(id) do
      {:ok, id} ->
        case Repo.get_by(SysNotice, notice_id: id, deleted: false) do
          nil -> {:error, :not_found}
          notice -> {:ok, notice}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc "在检查公告权限和资源范围后查询单个公告。"
  def get_notice(id, options) when is_list(options) do
    with {:ok, scope} <- Authorization.authorize_owner(options, "notice:read") do
      get_notice_scoped(id, scope)
    end
  end

  def create_notice(attrs, options)

  def create_notice(attrs, options) when is_map(attrs) and is_list(options) do
    with {:ok, _scope} <- Authorization.authorize_owner(options, "notice:create") do
      do_create_notice(attrs, Command.actor_id(options))
    end
  end

  def create_notice(_attrs, _options), do: {:error, :authorization_required}

  defp do_create_notice(attrs, actor_id) when is_map(attrs) do
    changeset = SysNotice.changeset(%SysNotice{}, normalize_attrs(attrs))
    changeset = Audit.put_actor(changeset, :creator_id, actor_id)
    Repo.insert(Ecto.Changeset.put_change(changeset, :owner_id, actor_id))
  end

  def update_notice(id, attrs, options)

  def update_notice(id, attrs, options) when is_map(attrs) and is_list(options) do
    with {:ok, scope} <- Authorization.authorize_owner(options, "notice:update") do
      do_update_notice(id, attrs, Command.actor_id(options), scope)
    end
  end

  def update_notice(_id, _attrs, _options), do: {:error, :authorization_required}

  @doc "Publishes or unpublishes a notice in the authenticated owner scope."
  def publish_notice(id, published, options)

  def publish_notice(id, published, options)
      when is_boolean(published) and is_list(options) do
    with {:ok, scope} <- Authorization.authorize_owner(options, "notice:update"),
         {:ok, notice} <- get_notice_scoped(id, scope) do
      changeset =
        notice
        |> Ecto.Changeset.change(%{
          published: published,
          publish_at: if(published, do: DateTime.utc_now(), else: nil)
        })
        |> Audit.put_actor(:updater_id, Command.actor_id(options))

      Repo.update(changeset)
    end
  end

  def publish_notice(_id, _published, _options), do: {:error, :authorization_required}

  def delete_notices(ids, options)

  def delete_notices(ids, options) when is_list(options) do
    with {:ok, scope} <- Authorization.authorize_owner(options, "notice:delete") do
      case do_delete_notices(ids, scope) do
        {:ok, _count} -> :ok
        error -> error
      end
    end
  end

  def delete_notices(_ids, _options), do: {:error, :authorization_required}

  @doc "Deletes notices and returns the number of records removed."
  def delete_notices_count(ids, options)

  def delete_notices_count(ids, options) when is_list(options) do
    with {:ok, scope} <- Authorization.authorize_owner(options, "notice:delete") do
      do_delete_notices(ids, scope)
    end
  end

  def delete_notices_count(_ids, _options), do: {:error, :authorization_required}

  defp list_notices_scoped(params, scope) do
    query =
      from(n in SysNotice,
        where: n.deleted == false,
        order_by: [desc: n.notice_id]
      )

    query = owner_filter(query, scope)
    query = filter_contains(query, :notice_title, params["noticeTitle"] || params[:notice_title])
    query = filter_integer(query, :notice_type, params["noticeType"] || params[:notice_type])
    query = filter_integer(query, :status, params["status"] || params[:status])
    paged = Pagination.page_rows(query, params, :notice_id)
    creator_names = creator_names(paged.rows)
    %{paged | rows: Enum.map(paged.rows, &notice_to_map(&1, creator_names))}
  end

  defp get_notice_scoped(id, scope) do
    case Params.parse_uuid(id) do
      {:ok, id} ->
        query = from(n in SysNotice, where: n.notice_id == ^id and n.deleted == false)

        case Repo.one(owner_filter(query, scope)) do
          nil -> {:error, :not_found}
          notice -> {:ok, notice}
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp do_update_notice(id, attrs, actor_id, scope) when is_map(attrs) do
    with {:ok, notice} <- get_notice_scoped(id, scope) do
      changeset = SysNotice.changeset(notice, normalize_attrs(attrs))
      Repo.update(Audit.put_actor(changeset, :updater_id, actor_id))
    end
  end

  defp do_delete_notices(ids, scope) when is_list(ids) do
    ids = ids |> Enum.map(&parse_uuid/1) |> Enum.uniq()

    if ids == [] or Enum.any?(ids, &is_nil/1) do
      {:error, :invalid_ids}
    else
      query = from(n in SysNotice, where: n.notice_id in ^ids and n.deleted == false)

      Repo.transaction(fn ->
        scoped = owner_filter(query, scope)
        count = Repo.aggregate(scoped, :count, :notice_id)

        if count != length(ids) do
          Repo.rollback(:not_found)
        else
          Repo.update_all(scoped, set: [deleted: true, update_time: DateTime.utc_now()])
          count
        end
      end)
      |> case do
        {:ok, count} -> {:ok, count}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp owner_filter(query, :all), do: query

  defp owner_filter(query, {:owner, owner_id}),
    do: where(query, [notice], notice.owner_id == ^owner_id)

  def notice_to_map(notice) do
    notice_to_map(notice, %{})
  end

  def notice_to_map(notice, creator_names) do
    %{
      "noticeId" => notice.notice_id,
      "noticeTitle" => notice.notice_title,
      "noticeType" => notice.notice_type,
      "noticeContent" => notice.notice_content,
      "status" => notice.status,
      "creatorName" => Map.get(creator_names, notice.creator_id, ""),
      "remark" => notice.remark,
      "createTime" => format_datetime(notice.create_time)
    }
  end

  @doc "Maps an internal notice to the Native notice DTO."
  def native_notice_to_map(notice, creator_names \\ %{}) do
    %{
      "id" => notice.notice_id,
      "title" => notice.notice_title,
      "content" => notice.notice_content,
      "noticeType" => native_notice_type(notice.notice_type),
      "published" => notice.published,
      "enabled" => notice.status == 1,
      "publishAt" => format_native_datetime(notice.publish_at),
      "createdBy" => Map.get(creator_names, notice.creator_id, notice.creator_id || ""),
      "createdAt" => format_native_datetime(notice.create_time)
    }
  end

  defp normalize_attrs(attrs) do
    Enum.reduce(@attrs, %{}, fn {json_key, atom_key}, normalized ->
      cond do
        Map.has_key?(attrs, json_key) ->
          Map.put(normalized, atom_key, normalize_attr(atom_key, Map.get(attrs, json_key)))

        Map.has_key?(attrs, atom_key) ->
          Map.put(normalized, atom_key, normalize_attr(atom_key, Map.get(attrs, atom_key)))

        true ->
          normalized
      end
    end)
  end

  defp normalize_attr(:notice_type, value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "notification" ->
        1

      "notice" ->
        1

      "announcement" ->
        2

      "bulletin" ->
        2

      value ->
        case Integer.parse(value) do
          {number, ""} -> number
          _ -> value
        end
    end
  end

  defp normalize_attr(:status, value) when is_boolean(value), do: if(value, do: 1, else: 0)
  defp normalize_attr(_key, value), do: value

  defp native_notice_rows(notices) do
    names = creator_names(notices)
    Enum.map(notices, &native_notice_to_map(&1, names))
  end

  defp native_notice_type(1), do: "notification"
  defp native_notice_type(2), do: "announcement"
  defp native_notice_type(type), do: to_string(type)

  defp creator_names(notices) do
    notices
    |> Enum.map(& &1.creator_id)
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> User.list_users_by_ids()
    |> Map.new(&{&1.user_id, &1.username})
  end

  defp filter_contains(query, _field, nil), do: query
  defp filter_contains(query, _field, ""), do: query

  defp filter_contains(query, field, value) do
    pattern = "%" <> String.trim(to_string(value)) <> "%"
    where(query, [notice], ilike(field(notice, ^field), ^pattern))
  end

  defp filter_integer(query, _field, nil), do: query
  defp filter_integer(query, _field, ""), do: query

  defp filter_integer(query, field, value) do
    case Integer.parse(to_string(value)) do
      {number, ""} -> where(query, [notice], field(notice, ^field) == ^number)
      _ -> query
    end
  end

  defp parse_uuid(value) do
    case Params.parse_uuid(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_native_datetime(nil), do: nil
  defp format_native_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp format_native_datetime(%NaiveDateTime{} = datetime),
    do: datetime |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
end
