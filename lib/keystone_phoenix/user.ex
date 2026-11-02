defmodule KeystonePhoenix.User do
  @moduledoc """
  Query boundary for system users.

  Passwords are stored for the upcoming local authentication flow but are
  never included in API maps.
  """

  import Ecto.Query

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  @default_page 1
  @default_page_size 10
  @max_page_size 500

  @spec list_users(map()) :: %{rows: list(), total: non_neg_integer()}
  def list_users(params \\ %{}) do
    query =
      from u in SysUser,
        where: u.deleted == false,
        order_by: [desc: u.user_id]

    query =
      query
      |> filter_integer(:user_id, params["userId"] || params[:user_id])
      |> filter_contains(:username, params["username"] || params[:username])
      |> filter_contains(:phone_number, params["phoneNumber"] || params[:phone_number])
      |> filter_integer(:status, params["status"] || params[:status])
      |> filter_integer(:dept_id, params["deptId"] || params[:dept_id])

    page_query(query, params)
  end

  @spec get_user(integer() | String.t()) :: {:ok, SysUser.t()} | {:error, :not_found}
  def get_user(id) do
    case Repo.get_by(SysUser, user_id: id, deleted: false) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @spec get_user_by_username(String.t()) :: {:ok, SysUser.t()} | {:error, :not_found}
  def get_user_by_username(username) when is_binary(username) do
    case Repo.get_by(SysUser, username: username, deleted: false) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def get_user_by_username(_username), do: {:error, :not_found}

  @spec user_to_map(SysUser.t()) :: map()
  def user_to_map(user) do
    %{
      "userId" => user.user_id,
      "postId" => user.post_id,
      "roleId" => user.role_id,
      "deptId" => user.dept_id,
      "username" => user.username,
      "nickname" => user.nickname,
      "userType" => user.user_type,
      "email" => user.email,
      "phoneNumber" => user.phone_number,
      "sex" => user.sex,
      "avatar" => user.avatar,
      "status" => user.status,
      "loginIp" => user.login_ip,
      "loginDate" => format_datetime(user.login_date),
      "isAdmin" => if(user.is_admin, do: 1, else: 0),
      "creatorId" => user.creator_id,
      "createTime" => format_datetime(user.create_time),
      "updaterId" => user.updater_id,
      "updateTime" => format_datetime(user.update_time),
      "remark" => user.remark
    }
  end

  defp page_query(query, params) do
    page = positive_integer(params["pageNum"] || params[:page_num], @default_page)
    page_size = positive_integer(params["pageSize"] || params[:page_size], @default_page_size)
    page_size = min(page_size, @max_page_size)

    total = Repo.aggregate(query, :count, :user_id)
    query = query |> limit(^page_size) |> offset(^((page - 1) * page_size))
    rows = Repo.all(query)

    %{total: total, rows: Enum.map(rows, &user_to_map/1)}
  end

  defp filter_integer(query, _field, nil), do: query
  defp filter_integer(query, _field, ""), do: query

  defp filter_integer(query, field, value) do
    case Integer.parse(to_string(value)) do
      {integer, ""} -> where(query, [record], field(record, ^field) == ^integer)
      _ -> query
    end
  end

  defp filter_contains(query, _field, nil), do: query
  defp filter_contains(query, _field, ""), do: query

  defp filter_contains(query, field, value) do
    value = "%#{String.trim(to_string(value))}%"
    where(query, [record], ilike(field(record, ^field), ^value))
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
