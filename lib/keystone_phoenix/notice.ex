defmodule KeystonePhoenix.Notice do
  @moduledoc "Query and command boundary for system notices."

  import Ecto.Query

  alias KeystonePhoenix.Audit
  alias KeystonePhoenix.Notice.SysNotice
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User

  @attrs [
    {"noticeTitle", :notice_title},
    {"noticeType", :notice_type},
    {"noticeContent", :notice_content},
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
    page = positive_integer(params["pageNum"] || params[:page_num], 1)
    page_size = min(positive_integer(params["pageSize"] || params[:page_size], 10), 500)
    total = Repo.aggregate(query, :count, :notice_id)
    rows = query |> limit(^page_size) |> offset(^((page - 1) * page_size)) |> Repo.all()
    creator_names = creator_names(rows)
    %{total: total, rows: Enum.map(rows, &notice_to_map(&1, creator_names))}
  end

  def get_notice(id) do
    case Params.parse_positive_integer(id) do
      {:ok, id} ->
        case Repo.get_by(SysNotice, notice_id: id, deleted: false) do
          nil -> {:error, :not_found}
          notice -> {:ok, notice}
        end

      :error ->
        {:error, :not_found}
    end
  end

  def create_notice(attrs, actor_id \\ nil)

  def create_notice(attrs, actor_id) when is_map(attrs) do
    changeset = SysNotice.changeset(%SysNotice{}, normalize_attrs(attrs))
    Repo.insert(Audit.put_actor(changeset, :creator_id, actor_id))
  end

  def create_notice(_attrs, _actor_id), do: {:error, invalid_changeset(:notice_title)}

  def update_notice(id, attrs, actor_id \\ nil)

  def update_notice(id, attrs, actor_id) when is_map(attrs) do
    with {:ok, notice} <- get_notice(id) do
      changeset = SysNotice.changeset(notice, normalize_attrs(attrs))
      Repo.update(Audit.put_actor(changeset, :updater_id, actor_id))
    end
  end

  def update_notice(_id, _attrs, _actor_id), do: {:error, invalid_changeset(:notice_title)}

  def delete_notices(ids) when is_list(ids) do
    ids = ids |> Enum.map(&parse_positive_integer/1) |> Enum.uniq()

    if ids == [] or Enum.any?(ids, &is_nil/1) do
      {:error, :invalid_ids}
    else
      case Repo.update_all(
             from(n in SysNotice, where: n.notice_id in ^ids and n.deleted == false),
             set: [deleted: true, update_time: DateTime.utc_now()]
           ) do
        {count, _} when count == length(ids) -> :ok
        _ -> {:error, :not_found}
      end
    end
  end

  def delete_notices(_ids), do: {:error, :invalid_ids}

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

  defp normalize_attrs(attrs) do
    Enum.reduce(@attrs, %{}, fn {json_key, atom_key}, normalized ->
      cond do
        Map.has_key?(attrs, json_key) -> Map.put(normalized, atom_key, Map.get(attrs, json_key))
        Map.has_key?(attrs, atom_key) -> Map.put(normalized, atom_key, Map.get(attrs, atom_key))
        true -> normalized
      end
    end)
  end

  defp creator_names(notices) do
    notices
    |> Enum.map(& &1.creator_id)
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
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

  defp positive_integer(nil, default), do: default

  defp positive_integer(value, default) do
    case Integer.parse(to_string(value)) do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} when number > 0 -> number
      _ -> nil
    end
  end

  defp parse_positive_integer(_value), do: nil

  defp invalid_changeset(field),
    do: Ecto.Changeset.add_error(Ecto.Changeset.change(%SysNotice{}), field, "参数无效")

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
