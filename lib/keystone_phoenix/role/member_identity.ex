defmodule KeystonePhoenix.Role.MemberIdentity do
  @moduledoc "角色成员身份列表的最小字段投影。"

  import Ecto.Query, only: [select: 3]

  alias KeystonePhoenix.Pagination

  # 身份列表只读取当前接口允许返回的字段，不加载其他个人资料。
  def page(query, params) do
    query
    |> select([user, _membership], %{
      id: user.user_id,
      username: user.username,
      displayName: user.nickname
    })
    |> Pagination.page_rows(params, :user_id)
  end
end
