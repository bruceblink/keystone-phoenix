defmodule KeystonePhoenixWeb.Live.AdminPages.System do
  @moduledoc "LiveView panels for system configuration, dictionaries, notices, and logs."

  use Phoenix.Component

  import KeystonePhoenixWeb.Live.AdminPages.Pagination
  import KeystonePhoenixWeb.Live.AdminPages.Modal
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminPages.Status

  def configs(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:active_modal, fn -> nil end)
      |> assign_new(:config_filter, fn -> %{"keyword" => ""} end)

    ~H"""
    <div class="configs-page system-page">
      <header class="page-heading">
        <div>
          <p class="eyebrow">SYSTEM / CONFIGURATION</p>
          <h1>系统配置</h1>
          <p class="page-description">查询运行参数、开关状态和配置说明。新增和编辑在模态框中完成。</p>
        </div>
        <div class="heading-actions">
          <button :if={!@read_only} type="button" class="refresh" phx-click="new-config" phx-disable-with="处理中…">新建配置</button>
          <button type="button" class="refresh secondary" phx-click="refresh-config" phx-disable-with="刷新中…">刷新配置</button>
        </div>
      </header>
      <%= if @config_feedback do %><p id="config-feedback" class={Feedback.class(@config_feedback)} role={Feedback.role(@config_feedback)} aria-live={Feedback.live(@config_feedback)}><%= Feedback.message(@config_feedback) %></p><% end %>
      <section class="card configs-filter-card filter-card">
        <form id="configs-filter" class="configs-filter-form filter-form" phx-change="filter-configs" phx-submit="filter-configs">
          <label for="configs-filter-keyword"><span>配置键或说明</span><input id="configs-filter-keyword" name="configKeyword" value={@config_filter["keyword"] || ""} placeholder="按配置键或说明筛选" autocomplete="off" /></label>
          <div class="configs-filter-actions filter-actions"><button type="submit" class="refresh">查询</button><button type="button" class="refresh secondary" phx-click="reset-config-filter">重置</button></div>
        </form>
      </section>
      <%= if @active_modal == "config" do %>
        <.modal id="config-modal" title={if @config_form["configId"] == "", do: "新建配置", else: "编辑配置"} description="维护系统配置和值域。">
    <form :if={!@read_only} aria-describedby="config-feedback" phx-submit="save-config">
        <input type="hidden" name="configId" value={@config_form["configId"]} />
        <div class="form-grid">
          <div><label for="config-name">配置名称</label><input id="config-name" name="configName" value={@config_form["configName"] || ""} required /></div>
          <div><label for="config-key">配置键</label><input id="config-key" name="configKey" value={@config_form["configKey"] || ""} required /></div>
          <div><label for="config-value">配置值</label><input id="config-value" name="configValue" value={@config_form["configValue"] || ""} required /></div>
          <div><label for="config-options">可选值（逗号分隔）</label><input id="config-options" name="configOptions" value={@config_form["configOptions"] || ""} /></div>
          <div><label for="config-change">允许修改</label><select id="config-change" name="isAllowChange"><option value="true" selected={@config_form["isAllowChange"] in [true, "true", 1, "1"]}>是</option><option value="false" selected={@config_form["isAllowChange"] in [false, "false", 0, "0"]}>否</option></select></div>
          <div class="wide"><label for="config-remark">备注</label><textarea id="config-remark" name="remark"><%= @config_form["remark"] || "" %></textarea></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存配置</button><button :if={@config_form["configId"] != ""} type="button" class="secondary" phx-click="close-modal" phx-value-modal="config" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
        </.modal>
      <% end %>
      <section class="card configs-table-card table-card" aria-labelledby="configs-table-title">
        <header class="card-header table-card-heading">
          <div><h2 id="configs-table-title">配置列表</h2><p>共 <%= length(filtered_config_rows(@config_rows, @config_filter)) %> 项匹配配置</p></div>
          <span class="status-badge status-badge--normal">LiveView</span>
        </header>
        <p :if={filtered_config_rows(@config_rows, @config_filter) == []} class="configs-empty table-empty" role="status"><strong>暂无配置数据</strong><span>没有匹配的系统配置，调整筛选条件后重试。</span></p>
        <div class="table-scroll" role="region" tabindex="0" aria-label="系统配置列表"><table class="configs-table"><caption class="sr-only">系统配置列表</caption><thead><tr><th scope="col">名称</th><th scope="col">键</th><th scope="col">值</th><th scope="col">允许修改</th><th scope="col">备注</th><th scope="col">操作</th></tr></thead><tbody>
          <%= for config <- filtered_config_rows(@config_rows, @config_filter) do %>
            <tr><td><strong><%= config["configName"] %></strong></td><td><code><%= config["configKey"] %></code></td><td><%= config["configValue"] %></td><td><%= config["isAllowChangeStr"] || if(config["isAllowChange"] == 1, do: "是", else: "否") %></td><td><%= config["remark"] || "" %></td><td :if={!@read_only}><button type="button" class="refresh" phx-click="edit-config" phx-value-config-id={config["configId"]} phx-disable-with="加载中…">编辑</button></td></tr>
          <% end %>
        </tbody></table></div>
      </section>
    </div>
    """
  end

  defp filtered_config_rows(rows, filter) do
    keyword = String.trim(to_string(filter["keyword"] || "")) |> String.downcase()

    Enum.filter(rows, fn config ->
      keyword == "" or
        String.contains?(
          String.downcase(
            "#{config["configName"] || ""} #{config["configKey"] || ""} #{config["remark"] || ""}"
          ),
          keyword
        )
    end)
  end

  def dicts(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:active_modal, fn -> nil end)
      |> assign_new(:dict_data_page_num, fn -> 1 end)
      |> assign_new(:dict_data_page_size, fn -> 50 end)
      |> assign_new(:dict_type_filter, fn -> %{"keyword" => ""} end)

    ~H"""
    <div class="dictionaries-page system-page">
      <header class="page-heading">
        <div>
          <p class="eyebrow">SYSTEM / DICTIONARIES</p>
          <h1>字典管理</h1>
          <p class="page-description">维护字典类型和可选值。先选择字典类型，再管理对应数据。</p>
        </div>
        <div class="heading-actions">
          <button :if={!@read_only} type="button" class="refresh" phx-click="new-dict-type" phx-disable-with="处理中…">新建字典类型</button>
          <button type="button" class="refresh secondary" phx-click="refresh-dicts" phx-disable-with="刷新中…">刷新字典</button>
        </div>
      </header>
      <%= if @dict_feedback do %><p id="dict-feedback" class={Feedback.class(@dict_feedback)} role={Feedback.role(@dict_feedback)} aria-live={Feedback.live(@dict_feedback)}><%= Feedback.message(@dict_feedback) %></p><% end %>
      <section class="card dictionaries-filter-card filter-card">
        <form id="dict-type-filter" class="dictionaries-filter-form filter-form" phx-submit="filter-dict-types">
          <label for="dict-type-filter-keyword"><span>类型编码或名称</span><input id="dict-type-filter-keyword" name="dictTypeKeyword" value={@dict_type_filter["keyword"] || ""} placeholder="按类型编码或名称筛选" autocomplete="off" /></label>
          <div class="dictionaries-filter-actions filter-actions"><button type="submit" class="refresh">查询</button><button type="button" class="refresh secondary" phx-click="reset-dict-type-filter">重置</button></div>
        </form>
      </section>
      <p :if={filtered_dict_type_rows(@dict_type_rows, @dict_type_filter) == [] and @dict_data_rows == []} class="dictionaries-empty table-empty" role="status"><strong>暂无字典数据</strong><span>字典类型和可选值加载后会显示在这里。</span></p>
      <%= if @active_modal == "dict-type" do %>
        <.modal id="dict-type-modal" title={if @dict_type_form["dictId"] == "", do: "新建字典类型", else: "编辑字典类型"} description="维护字典类型和状态。">
    <form :if={!@read_only} aria-describedby="dict-feedback" phx-submit="save-dict-type">
        <input type="hidden" name="dictId" value={@dict_type_form["dictId"]} />
        <div class="form-grid">
          <div><label for="dict-name">字典名称</label><input id="dict-name" name="dictName" value={@dict_type_form["dictName"] || ""} required /></div>
          <div><label for="dict-type">字典类型</label><input id="dict-type" name="dictType" value={@dict_type_form["dictType"] || ""} required /></div>
          <div><label for="dict-status">状态</label><select id="dict-status" name="status"><option value="1" selected={@dict_type_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@dict_type_form["status"] in [0, "0"]}>停用</option></select></div>
          <div><label for="dict-remark">备注</label><input id="dict-remark" name="remark" value={@dict_type_form["remark"] || ""} /></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存字典类型</button><button :if={@dict_type_form["dictId"] != ""} type="button" class="secondary" phx-click="close-modal" phx-value-modal="dict-type" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
        </.modal>
      <% end %>
      <section class="card dictionary-types-card table-card" aria-labelledby="dict-types-title">
        <header class="card-header table-card-heading">
          <div><h2 id="dict-types-title">字典类型</h2><p>共 <%= length(filtered_dict_type_rows(@dict_type_rows, @dict_type_filter)) %> 个匹配类型</p></div>
          <span class="status-badge status-badge--normal">可维护</span>
        </header>
        <div class="table-scroll" role="region" tabindex="0" aria-label="字典类型列表"><table class="dictionary-types-table"><caption class="sr-only">字典类型列表</caption><thead><tr><th scope="col">名称</th><th scope="col">类型</th><th scope="col">状态</th><th scope="col">备注</th><th scope="col">操作</th></tr></thead><tbody>
          <%= for dict <- filtered_dict_type_rows(@dict_type_rows, @dict_type_filter) do %>
            <tr><td><strong><%= dict["dictName"] %></strong></td><td><code><%= dict["dictType"] %></code></td><td><span class={"status-badge #{Status.normal_paused(dict["status"])}"}><%= if dict["status"] == 1, do: "正常", else: "停用" %></span></td><td><%= dict["remark"] || "" %></td><td class="table-actions"><button type="button" class="refresh" phx-click="select-dict-type" phx-value-dict-type={dict["dictType"]} phx-disable-with="加载中…">查看数据</button><button :if={!@read_only} type="button" class="refresh" phx-click="edit-dict-type" phx-value-dict-id={dict["dictId"]} phx-disable-with="加载中…">编辑</button><button :if={!@read_only} type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-dict-type" phx-value-dict-id={dict["dictId"]} phx-disable-with="删除中…">删除</button></td></tr>
          <% end %>
        </tbody></table></div>
      </section>
      <section class="card dictionary-items-card table-card" aria-labelledby="dict-items-title">
        <header class="card-header table-card-heading">
          <div><h2 id="dict-items-title">字典数据（<%= @selected_dict_type || "未选择" %>）</h2><p>当前类型的标签、值和展示属性</p></div>
          <div class="heading-actions"><button :if={!@read_only} type="button" class="refresh" phx-click="new-dict-data" phx-disable-with="处理中…">新建字典数据</button></div>
        </header>
      <%= if @active_modal == "dict-data" do %>
        <.modal id="dict-data-modal" title={if @dict_data_form["dictCode"] == "", do: "新建字典数据", else: "编辑字典数据"} description="维护字典标签、值和展示属性。">
    <form :if={!@read_only} aria-describedby="dict-feedback" phx-submit="save-dict-data">
        <input type="hidden" name="dictCode" value={@dict_data_form["dictCode"]} />
        <div class="form-grid">
          <div><label for="dict-data-type">字典类型</label><input id="dict-data-type" name="dictType" value={@dict_data_form["dictType"] || @selected_dict_type || ""} required /></div>
          <div><label for="dict-label">标签</label><input id="dict-label" name="dictLabel" value={@dict_data_form["dictLabel"] || ""} required /></div>
          <div><label for="dict-value">值</label><input id="dict-value" name="dictValue" value={@dict_data_form["dictValue"] || ""} required /></div>
          <div><label for="dict-sort">排序</label><input id="dict-sort" type="number" name="dictSort" value={@dict_data_form["dictSort"] || 0} /></div>
          <div><label for="dict-default">默认值</label><select id="dict-default" name="isDefault"><option value="true" selected={@dict_data_form["isDefault"] in [true, "true", 1, "1"]}>是</option><option value="false" selected={@dict_data_form["isDefault"] in [false, "false", 0, "0"]}>否</option></select></div>
          <div><label for="dict-data-status">状态</label><select id="dict-data-status" name="status"><option value="1" selected={@dict_data_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@dict_data_form["status"] in [0, "0"]}>停用</option></select></div>
          <div><label for="dict-css">CSS 类</label><input id="dict-css" name="cssClass" value={@dict_data_form["cssClass"] || ""} /></div>
          <div><label for="dict-list">列表类</label><input id="dict-list" name="listClass" value={@dict_data_form["listClass"] || ""} /></div>
          <div class="wide"><label for="dict-data-remark">备注</label><textarea id="dict-data-remark" name="remark"><%= @dict_data_form["remark"] || "" %></textarea></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存字典数据</button><button :if={@dict_data_form["dictCode"] != ""} type="button" class="secondary" phx-click="close-modal" phx-value-modal="dict-data" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
        </.modal>
      <% end %>
        <div class="table-scroll" role="region" tabindex="0" aria-label="字典数据列表"><table class="dictionary-items-table"><caption class="sr-only">字典数据列表</caption><thead><tr><th scope="col">标签</th><th scope="col">值</th><th scope="col">排序</th><th scope="col">默认</th><th scope="col">状态</th><th scope="col">操作</th></tr></thead><tbody>
            <%= for data <- page_rows(@dict_data_rows, @dict_data_page_num, @dict_data_page_size) do %>
            <tr><td><strong><%= data["dictLabel"] %></strong></td><td><code><%= data["dictValue"] %></code></td><td><%= data["dictSort"] %></td><td><%= if data["isDefault"] == 1, do: "是", else: "否" %></td><td><span class={"status-badge #{Status.normal_paused(data["status"])}"}><%= if data["status"] == 1, do: "正常", else: "停用" %></span></td><td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="edit-dict-data" phx-value-dict-code={data["dictCode"]} phx-disable-with="加载中…">编辑</button><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-dict-data" phx-value-dict-code={data["dictCode"]} phx-disable-with="删除中…">删除</button></td></tr>
          <% end %>
        </tbody></table></div>
        <.pagination panel="dict-data" page_num={min(@dict_data_page_num, page_count(length(@dict_data_rows), @dict_data_page_size))} page_size={@dict_data_page_size} total={length(@dict_data_rows)} />
      </section>
    </div>
    """
  end

  defp filtered_dict_type_rows(rows, filter) do
    keyword = String.trim(to_string(filter["keyword"] || "")) |> String.downcase()

    Enum.filter(rows, fn dict_type ->
      keyword == "" or
        String.contains?(
          String.downcase("#{dict_type["dictName"] || ""} #{dict_type["dictType"] || ""}"),
          keyword
        )
    end)
  end

  def notices(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:active_modal, fn -> nil end)
      |> assign_new(:notice_filter, fn -> %{"title" => "", "published" => "all"} end)

    ~H"""
    <div class="notices-page system-page">
      <header class="page-heading">
        <div>
          <p class="eyebrow">SYSTEM / NOTICES</p>
          <h1>通知公告</h1>
          <p class="page-description">查询公告内容、状态和发布时间。新增和编辑在模态框中完成。</p>
        </div>
        <div class="heading-actions">
          <button :if={!@read_only} type="button" class="refresh" phx-click="new-notice" phx-disable-with="处理中…">新增公告</button>
          <button type="button" class="refresh secondary" phx-click="refresh-notices" phx-disable-with="刷新中…">刷新公告</button>
        </div>
      </header>
      <%= if @notice_feedback do %><p id="notice-feedback" class={Feedback.class(@notice_feedback)} role={Feedback.role(@notice_feedback)} aria-live={Feedback.live(@notice_feedback)}><%= Feedback.message(@notice_feedback) %></p><% end %>
      <section class="card notices-filter-card filter-card">
        <form id="notice-filter" class="notices-filter-form filter-form" phx-change="filter-notices" phx-submit="filter-notices">
          <label for="notice-filter-title"><span>标题或内容</span><input id="notice-filter-title" name="noticeTitle" value={@notice_filter["title"] || ""} placeholder="按标题、内容或类型筛选" /></label>
          <label for="notice-filter-published"><span>发布状态</span><select id="notice-filter-published" name="published"><option value="all" selected={@notice_filter["published"] in [nil, "all"]}>全部状态</option><option value="true" selected={@notice_filter["published"] == "true"}>已发布</option><option value="false" selected={@notice_filter["published"] == "false"}>未发布</option></select></label>
          <div class="notices-filter-actions filter-actions"><button type="submit" class="refresh">查询</button><button type="button" class="refresh secondary" phx-click="reset-notice-filter">重置</button></div>
        </form>
      </section>
      <%= if @active_modal == "notice" do %>
        <.modal id="notice-modal" title={if @notice_form["noticeId"] == "", do: "新建公告", else: "编辑公告"} description="维护公告内容、状态和备注。">
    <form :if={!@read_only} aria-describedby="notice-feedback" phx-submit="save-notice">
        <input type="hidden" name="noticeId" value={@notice_form["noticeId"]} />
        <div class="form-grid">
          <div><label for="notice-title">标题</label><input id="notice-title" name="noticeTitle" value={@notice_form["noticeTitle"] || ""} required /></div>
          <div><label for="notice-type">类型</label><select id="notice-type" name="noticeType"><option value="1" selected={@notice_form["noticeType"] in [1, "1"]}>通知</option><option value="2" selected={@notice_form["noticeType"] in [2, "2"]}>公告</option></select></div>
          <div class="wide"><label for="notice-content">内容</label><textarea id="notice-content" name="noticeContent" required><%= @notice_form["noticeContent"] || "" %></textarea></div>
          <div><label for="notice-status">状态</label><select id="notice-status" name="status"><option value="1" selected={@notice_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@notice_form["status"] in [0, "0"]}>停用</option></select></div>
          <div><label for="notice-remark">备注</label><input id="notice-remark" name="remark" value={@notice_form["remark"] || ""} /></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存公告</button><button :if={@notice_form["noticeId"] != ""} type="button" class="secondary" phx-click="close-modal" phx-value-modal="notice" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
        </.modal>
      <% end %>
      <section class="card notices-table-card table-card" aria-labelledby="notices-table-title">
        <header class="card-header table-card-heading">
          <div><h2 id="notices-table-title">公告列表</h2><p>共 <%= length(filtered_notice_rows(@notice_rows, @notice_filter)) %> 条匹配公告</p></div>
          <span class="status-badge status-badge--normal">LiveView</span>
        </header>
        <p :if={filtered_notice_rows(@notice_rows, @notice_filter) == []} class="notices-empty table-empty" role="status"><strong>暂无公告数据</strong><span>没有匹配的公告，调整筛选条件后重试。</span></p>
        <div class="table-scroll" role="region" tabindex="0" aria-label="公告列表"><table class="notices-table"><caption class="sr-only">公告列表</caption><thead><tr><th scope="col">标题</th><th scope="col">类型</th><th scope="col">内容</th><th scope="col">状态</th><th scope="col">发布状态</th><th scope="col">备注</th><th scope="col">创建时间</th><th scope="col">操作</th></tr></thead><tbody>
          <%= for notice <- filtered_notice_rows(@notice_rows, @notice_filter) do %>
            <tr><td><strong><%= notice["noticeTitle"] %></strong></td><td><%= if notice["noticeType"] == 1, do: "通知", else: "公告" %></td><td class="notice-content" title={notice["noticeContent"]}><%= notice["noticeContent"] %></td><td><span class={"status-badge #{Status.normal_paused(notice["status"])}"}><%= if notice["status"] == 1, do: "正常", else: "停用" %></span></td><td><span class={"status-badge #{Status.published(notice["published"])}"}><%= if notice["published"], do: "已发布", else: "未发布" %></span></td><td><%= notice["remark"] || "" %></td><td><%= notice["createTime"] || "" %></td><td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="edit-notice" phx-value-notice-id={notice["noticeId"]} phx-disable-with="加载中…">编辑</button><button type="button" class="refresh" phx-click="toggle-notice-status" phx-value-notice-id={notice["noticeId"]} phx-value-status={if notice["status"] == 1, do: 0, else: 1} phx-disable-with="处理中…"><%= if notice["status"] == 1, do: "停用", else: "启用" %></button><button type="button" class="refresh" phx-click="publish-notice" phx-value-notice-id={notice["noticeId"]} phx-value-published={if notice["published"], do: "false", else: "true"} phx-disable-with="处理中…"><%= if notice["published"], do: "取消发布", else: "发布" %></button><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-notice" phx-value-notice-id={notice["noticeId"]} phx-disable-with="删除中…">删除</button></td></tr>
          <% end %>
        </tbody></table></div>
      </section>
    </div>
    """
  end

  defp filtered_notice_rows(rows, filter) do
    title = String.trim(to_string(filter["title"] || "")) |> String.downcase()
    published = filter["published"] || "all"

    Enum.filter(rows, fn notice ->
      text =
        "#{notice["noticeTitle"] || ""} #{notice["noticeContent"] || ""}" |> String.downcase()

      title_match? = title == "" or String.contains?(text, title)

      published_match? =
        published == "all" or
          (published == "true" and notice["published"] == true) or
          (published == "false" and notice["published"] != true)

      title_match? and published_match?
    end)
  end

  def logs(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:login_page_num, fn -> 1 end)
      |> assign_new(:operation_page_num, fn -> 1 end)
      |> assign_new(:page_size, fn -> 50 end)
      |> assign_new(:kind, fn -> "both" end)
      |> assign_new(:login_log_filter, fn -> %{"username" => "", "status" => ""} end)
      |> assign_new(:operation_log_filter, fn ->
        %{"actor" => "", "action" => "", "resource" => ""}
      end)

    ~H"""
    <div class="audit-page system-page">
      <header class="page-heading">
        <div>
          <p class="eyebrow">OPERATIONS / AUDIT</p>
          <h1><%= if @kind == "login", do: "登录日志", else: if(@kind == "operation", do: "操作审计", else: "审计日志") %></h1>
          <p class="page-description">查看登录和操作记录，保留分页、删除和只读权限控制。</p>
        </div>
        <div class="heading-actions">
          <button :if={@kind == "both"} type="button" class="refresh" phx-click="refresh-logs" phx-disable-with="刷新中…">刷新日志</button>
          <button :if={@kind == "login"} type="button" class="refresh secondary" phx-click="export-login-logs" phx-disable-with="导出中…">导出 Excel</button>
          <button :if={@kind == "login"} type="button" class="refresh" phx-click="refresh-login-logs" phx-disable-with="刷新中…">刷新登录日志</button>
          <button :if={@kind == "operation"} type="button" class="refresh secondary" phx-click="export-operation-logs" phx-disable-with="导出中…">导出 Excel</button>
          <button :if={@kind == "operation"} type="button" class="refresh" phx-click="refresh-operation-logs" phx-disable-with="刷新中…">刷新操作日志</button>
        </div>
      </header>
      <%= if @log_feedback do %><p id="log-feedback" class={Feedback.class(@log_feedback)} role={Feedback.role(@log_feedback)} aria-live={Feedback.live(@log_feedback)}><%= Feedback.message(@log_feedback) %></p><% end %>
      <span id="audit-download-hook" phx-hook="DownloadFile" hidden></span>
      <%= if @kind in ["both", "login"] do %>
      <section class="card audit-filter-card filter-card">
        <form id="login-log-filter" class="audit-filter-form filter-form" phx-submit="filter-login-logs">
          <label for="login-log-filter-username"><span>用户名</span><input id="login-log-filter-username" name="loginUsername" value={@login_log_filter["username"] || ""} placeholder="按用户名筛选" autocomplete="off" /></label>
          <label for="login-log-filter-status"><span>登录状态</span><input id="login-log-filter-status" name="loginStatus" value={@login_log_filter["status"] || ""} placeholder="例如 SUCCESS、FAILURE" autocomplete="off" /></label>
          <div class="audit-filter-actions filter-actions"><button type="submit" class="refresh">查询</button><button type="button" class="refresh secondary" phx-click="reset-login-log-filter">重置</button></div>
        </form>
      </section>
      <section class="card audit-table-card table-card" aria-labelledby="login-logs-title">
        <header class="card-header table-card-heading">
          <div><h2 id="login-logs-title">登录日志</h2><p>共 <%= length(@login_log_rows) %> 条记录</p></div>
          <span class="status-badge status-badge--normal">只读审计</span>
        </header>
        <p :if={@login_log_rows == []} class="audit-empty table-empty" role="status"><strong>暂无登录日志数据</strong><span>新的登录记录会显示在这里。</span></p>
        <div class="table-scroll" role="region" tabindex="0" aria-label="登录日志列表"><table class="audit-table"><caption class="sr-only">登录日志列表</caption><thead><tr><th scope="col">用户</th><th scope="col">IP</th><th scope="col">浏览器</th><th scope="col">状态</th><th scope="col">消息</th><th scope="col">时间</th></tr></thead><tbody>
            <%= for log <- page_rows(@login_log_rows, @login_page_num, @page_size) do %>
            <tr><td><strong><%= log["username"] %></strong></td><td><code><%= log["ipAddress"] %></code></td><td><%= log["browser"] %></td><td><span class={"status-badge #{Status.success_failure(log["status"])}"}><%= if log["status"] == 1, do: "成功", else: "失败" %></span></td><td><%= log["msg"] %></td><td><%= log["loginTime"] %></td></tr>
          <% end %>
        </tbody></table></div>
        <.pagination panel="login-logs" page_num={min(@login_page_num, page_count(length(@login_log_rows), @page_size))} page_size={@page_size} total={length(@login_log_rows)} />
      </section>
      <% end %>
      <%= if @kind in ["both", "operation"] do %>
      <section class="card audit-filter-card filter-card">
        <form id="operation-log-filter" class="audit-filter-form filter-form" phx-submit="filter-operation-logs">
          <label for="operation-log-filter-actor"><span>操作用户</span><input id="operation-log-filter-actor" name="operationActor" value={@operation_log_filter["actor"] || ""} placeholder="按用户名筛选" autocomplete="off" /></label>
          <label for="operation-log-filter-action"><span>操作动作</span><input id="operation-log-filter-action" name="operationAction" value={@operation_log_filter["action"] || ""} placeholder="例如 UPDATE、DELETE" autocomplete="off" /></label>
          <label for="operation-log-filter-resource"><span>资源类型</span><input id="operation-log-filter-resource" name="operationResource" value={@operation_log_filter["resource"] || ""} placeholder="例如 user、role" autocomplete="off" /></label>
          <div class="audit-filter-actions filter-actions"><button type="submit" class="refresh">查询</button><button type="button" class="refresh secondary" phx-click="reset-operation-log-filter">重置</button></div>
        </form>
      </section>
      <section class="card audit-table-card table-card" aria-labelledby="operation-logs-title">
        <header class="card-header table-card-heading">
          <div><h2 id="operation-logs-title">操作审计</h2><p>共 <%= length(@operation_log_rows) %> 条记录</p></div>
          <span class="status-badge status-badge--normal">只读审计</span>
        </header>
        <p :if={@operation_log_rows == []} class="audit-empty table-empty" role="status"><strong>暂无操作日志数据</strong><span>新的操作记录会显示在这里。</span></p>
        <div class="table-scroll" role="region" tabindex="0" aria-label="操作日志列表"><table class="audit-table"><caption class="sr-only">操作日志列表</caption><thead><tr><th scope="col">用户</th><th scope="col">模块</th><th scope="col">方法</th><th scope="col">请求地址</th><th scope="col">状态</th><th scope="col">时间</th></tr></thead><tbody>
            <%= for log <- page_rows(@operation_log_rows, @operation_page_num, @page_size) do %>
            <tr><td><strong><%= log["username"] %></strong></td><td><%= log["requestModule"] %></td><td><code><%= log["requestMethod"] %></code></td><td><code><%= log["requestUrl"] %></code></td><td><span class={"status-badge #{Status.success_failure(log["status"])}"}><%= if log["status"] == 1, do: "成功", else: "失败" %></span></td><td><%= log["operationTime"] %></td></tr>
          <% end %>
        </tbody></table></div>
        <.pagination panel="operation-logs" page_num={min(@operation_page_num, page_count(length(@operation_log_rows), @page_size))} page_size={@page_size} total={length(@operation_log_rows)} />
      </section>
      <% end %>
    </div>
    """
  end
end
