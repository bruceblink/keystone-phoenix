defmodule KeystonePhoenixWeb.Live.AdminPages.OrganizationFilters do
  @moduledoc "组织管理页面的本地筛选和事件参数转换。"

  # 组织页面先按当前已加载的数据过滤，查询动作不会改变后端数据范围。
  def filtered_depts(rows, filter), do: filter_rows(rows, filter, ["deptName", "leaderName"])

  def filtered_posts(rows, filter), do: filter_rows(rows, filter, ["postCode", "postName"])

  def filtered_roles(rows, filter), do: filter_rows(rows, filter, ["roleKey", "roleName"])

  def filtered_menus(rows, keyword) do
    keyword = String.downcase(String.trim(to_string(keyword || "")))

    if keyword == "" do
      rows
    else
      Enum.filter(rows, fn row ->
        haystack =
          [row["menuCode"], row["menuName"], row["permission"], row["path"]]
          |> Enum.map_join(" ", &to_string(&1 || ""))
          |> String.downcase()

        String.contains?(haystack, keyword)
      end)
    end
  end

  def organization_filter(params, previous, [keyword_key, status_key]) do
    if params["reset"] == "true" do
      %{"keyword" => "", "status" => "all"}
    else
      previous = previous || %{"keyword" => "", "status" => "all"}

      %{
        "keyword" => String.trim(params[keyword_key] || previous["keyword"] || ""),
        "status" => params[status_key] || previous["status"] || "all"
      }
    end
  end

  def menu_filter(params, previous) do
    if params["reset"] == "true" do
      ""
    else
      String.trim(params["menuKeyword"] || previous || "")
    end
  end

  defp filter_rows(rows, filter, fields) do
    keyword = String.downcase(String.trim(to_string(filter["keyword"] || "")))
    status = to_string(filter["status"] || "all")

    Enum.filter(rows, fn row ->
      haystack = fields |> Enum.map_join(" ", &to_string(row[&1] || "")) |> String.downcase()
      keyword_match = keyword == "" or String.contains?(haystack, keyword)
      status_match = status == "all" or to_string(row["status"]) == status
      keyword_match and status_match
    end)
  end
end
