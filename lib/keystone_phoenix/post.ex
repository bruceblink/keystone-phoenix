defmodule KeystonePhoenix.Post do
  @moduledoc "Query boundary for post management."

  import Ecto.Query

  alias KeystonePhoenix.Audit
  alias KeystonePhoenix.Post.SysPost
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  @post_attrs [
    {"postCode", :post_code},
    {"postName", :post_name},
    {"postSort", :post_sort},
    {"status", :status},
    {"remark", :remark}
  ]

  def list_posts(params \\ %{}) do
    query =
      from(p in SysPost,
        where: p.deleted == false,
        order_by: [asc: p.post_sort, asc: p.post_id]
      )

    query = filter_contains(query, :post_code, params["postCode"] || params[:post_code])
    query = filter_contains(query, :post_name, params["postName"] || params[:post_name])
    query = filter_status(query, params["status"] || params[:status])

    page = positive_integer(params["pageNum"] || params[:page_num], 1)
    page_size = min(positive_integer(params["pageSize"] || params[:page_size], 10), 500)
    total = Repo.aggregate(query, :count, :post_id)
    rows = query |> limit(^page_size) |> offset(^((page - 1) * page_size)) |> Repo.all()
    %{total: total, rows: Enum.map(rows, &post_to_map/1)}
  end

  def get_post(id) do
    case Repo.get_by(SysPost, post_id: id, deleted: false) do
      nil -> {:error, :not_found}
      post -> {:ok, post}
    end
  end

  @doc "Returns active posts keyed by ID with one database query."
  def list_posts_by_ids(ids) when is_list(ids) do
    ids = ids |> Enum.map(&parse_positive_integer/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      []
    else
      from(post in SysPost, where: post.deleted == false and post.post_id in ^ids)
      |> Repo.all()
    end
  end

  def list_posts_by_ids(_ids), do: []

  def create_post(attrs, actor_id \\ nil)

  def create_post(attrs, actor_id) when is_map(attrs) do
    attrs
    |> normalize_attrs()
    |> then(&SysPost.changeset(%SysPost{}, &1))
    |> Audit.put_actor(:creator_id, actor_id)
    |> Repo.insert()
  end

  def create_post(_attrs, _actor_id), do: {:error, invalid_changeset(:post_code)}

  def update_post(id, attrs, actor_id \\ nil)

  def update_post(id, attrs, actor_id) when is_map(attrs) do
    with {:ok, post} <- get_post(id) do
      post
      |> SysPost.changeset(normalize_attrs(attrs))
      |> Audit.put_actor(:updater_id, actor_id)
      |> Repo.update()
    end
  end

  def update_post(_id, _attrs, _actor_id), do: {:error, invalid_changeset(:post_code)}

  def delete_posts(ids, actor_id \\ nil)

  def delete_posts(ids, actor_id) when is_list(ids) do
    ids = ids |> Enum.map(&parse_positive_integer/1) |> Enum.uniq()

    if ids == [] or Enum.any?(ids, &is_nil/1) do
      {:error, :invalid_ids}
    else
      case Repo.transaction(fn -> delete_posts_in_transaction(ids, actor_id) end) do
        {:ok, :ok} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def delete_posts(_ids, _actor_id), do: {:error, :invalid_ids}

  def post_to_map(post) do
    %{
      "postId" => post.post_id,
      "postCode" => post.post_code,
      "postName" => post.post_name,
      "postSort" => post.post_sort,
      "status" => post.status,
      "statusStr" => status_label(post.status),
      "remark" => post.remark,
      "createTime" => format_datetime(post.create_time)
    }
  end

  defp delete_posts_in_transaction(ids, actor_id) do
    Enum.each(ids, fn post_id ->
      case get_post(post_id) do
        {:error, :not_found} ->
          Repo.rollback(:not_found)

        {:ok, post} ->
          if user_count(post_id) > 0 do
            Repo.rollback(:has_users)
          else
            changeset = Ecto.Changeset.change(post, deleted: true)
            changeset = Audit.put_actor(changeset, :updater_id, actor_id)

            case Repo.update(changeset) do
              {:ok, _deleted} -> :ok
              {:error, _changeset} -> Repo.rollback(:update_failed)
            end
          end
      end
    end)

    :ok
  end

  defp user_count(post_id) do
    from(u in SysUser, where: u.post_id == ^post_id and u.deleted == false)
    |> Repo.aggregate(:count, :user_id)
  end

  defp normalize_attrs(attrs) do
    Enum.reduce(@post_attrs, %{}, fn {json_key, atom_key}, normalized ->
      cond do
        Map.has_key?(attrs, json_key) -> Map.put(normalized, atom_key, Map.get(attrs, json_key))
        Map.has_key?(attrs, atom_key) -> Map.put(normalized, atom_key, Map.get(attrs, atom_key))
        true -> normalized
      end
    end)
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer > 0 -> integer
      _ -> nil
    end
  end

  defp parse_positive_integer(_value), do: nil

  defp status_label(1), do: "正常"
  defp status_label(0), do: "停用"
  defp status_label(status), do: to_string(status || "")

  defp invalid_changeset(field),
    do: Ecto.Changeset.add_error(Ecto.Changeset.change(%SysPost{}), field, "参数无效")

  defp filter_contains(query, _field, nil), do: query
  defp filter_contains(query, _field, ""), do: query

  defp filter_contains(query, field, value) do
    pattern = "%" <> String.trim(to_string(value)) <> "%"
    where(query, [post], ilike(field(post, ^field), ^pattern))
  end

  defp filter_status(query, nil), do: query
  defp filter_status(query, ""), do: query

  defp filter_status(query, value) do
    case Integer.parse(to_string(value)) do
      {status, ""} -> where(query, [post], post.status == ^status)
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

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
