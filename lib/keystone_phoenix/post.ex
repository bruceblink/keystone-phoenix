defmodule KeystonePhoenix.Post do
  @moduledoc "Query boundary for post management."

  import Ecto.Query

  alias KeystonePhoenix.Post.SysPost
  alias KeystonePhoenix.Repo

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

  def post_to_map(post) do
    %{
      "postId" => post.post_id,
      "postCode" => post.post_code,
      "postName" => post.post_name,
      "postSort" => post.post_sort,
      "status" => post.status,
      "remark" => post.remark,
      "createTime" => format_datetime(post.create_time)
    }
  end

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
