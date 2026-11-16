defmodule KeystonePhoenixWeb.Live.AdminPages.FilterNavigation do
  @moduledoc "组织树页面筛选条件的深链接参数转换。"

  @doc "读取与 admin-web 相同的页面关键词参数。"
  def keyword(params, key), do: String.trim(params[key] || params["keyword"] || "")

  @doc "返回当前页面需要写入的筛选 assign。"
  def assigns("menus", params), do: [menu_filter: keyword(params, "menus_keyword")]

  def assigns("depts", params),
    do: [dept_filter: %{"keyword" => keyword(params, "departments_keyword"), "status" => "all"}]

  def assigns(_panel, _params), do: []

  @doc "生成与 admin-web 页面命名空间一致的筛选深链接。"
  def path("menus", ""), do: "/menus"
  def path("depts", ""), do: "/departments"
  def path("menus", keyword), do: "/menus?menus_keyword=#{URI.encode(keyword)}"
  def path("depts", keyword), do: "/departments?departments_keyword=#{URI.encode(keyword)}"
end
