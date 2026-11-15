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
      by_id = Map.new(rows, &{menu_id(&1), &1})

      matching_rows = Enum.filter(rows, &menu_matches?(&1, keyword))

      matching_rows
      |> Enum.reduce(MapSet.new(), &add_menu_ancestors(&2, &1, by_id))
      |> then(fn visible_ids ->
        Enum.filter(rows, fn row ->
          (is_nil(menu_id(row)) and row in matching_rows) or menu_id(row) in visible_ids
        end)
      end)
    end
  end

  @doc "返回当前菜单编辑时允许选择的父级，排除当前节点及全部后代。"
  def menu_parent_rows(rows, current_id) do
    excluded =
      current_id
      |> to_string()
      |> case do
        "" -> MapSet.new()
        id -> descendant_ids(rows, id, MapSet.new([id]))
      end

    Enum.reject(rows, &(to_string(menu_id(&1) || "") in excluded))
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

  defp menu_matches?(row, keyword) do
    [row["menuCode"], row["code"], row["menuName"], row["name"], row["permission"], row["path"]]
    |> Enum.map_join(" ", &to_string(&1 || ""))
    |> String.downcase()
    |> String.contains?(keyword)
  end

  defp add_menu_ancestors(visible_ids, row, by_id),
    do: collect_menu_ancestors(row, visible_ids, by_id, MapSet.new())

  defp collect_menu_ancestors(nil, visible_ids, _by_id, _seen), do: visible_ids

  defp collect_menu_ancestors(row, visible_ids, by_id, seen) do
    id = menu_id(row)

    if is_nil(id) or MapSet.member?(seen, id) do
      visible_ids
    else
      collect_menu_ancestors(
        Map.get(by_id, parent_id(row)),
        MapSet.put(visible_ids, id),
        by_id,
        MapSet.put(seen, id)
      )
    end
  end

  defp descendant_ids(rows, target_parent_id, seen) do
    children = Enum.filter(rows, &(to_string(parent_id(&1) || "") == target_parent_id))

    Enum.reduce(children, seen, fn child, ids ->
      child_id = to_string(menu_id(child) || "")

      if child_id == "" or MapSet.member?(ids, child_id) do
        ids
      else
        descendant_ids(rows, to_string(child_id), MapSet.put(ids, child_id))
      end
    end)
  end

  defp menu_id(row), do: row["menuId"] || row["id"]
  defp parent_id(row), do: row["parentId"]
end
