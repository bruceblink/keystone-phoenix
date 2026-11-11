defmodule KeystonePhoenixWeb.Live.AdminPages.System do
  @moduledoc "LiveView panels for system configuration, dictionaries, notices, and logs."

  use Phoenix.Component

  import KeystonePhoenixWeb.Live.AdminPages.Pagination
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminPages.Status

  def configs(assigns) do
    assigns = assign_new(assigns, :read_only, fn -> false end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button :if={!@read_only} type="button" class="refresh" phx-click="new-config" phx-disable-with="处理中…">新建配置</button><button type="button" class="refresh secondary" phx-click="refresh-config" phx-disable-with="刷新中…">刷新配置</button></div>
      <%= if @config_feedback do %><p id="config-feedback" class={Feedback.class(@config_feedback)} role={Feedback.role(@config_feedback)} aria-live={Feedback.live(@config_feedback)}><%= Feedback.message(@config_feedback) %></p><% end %>
      <p :if={@config_rows == []} class="table-empty" role="status">暂无配置数据</p>
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
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存配置</button><button :if={@config_form["configId"] != ""} type="button" class="secondary" phx-click="new-config" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
      <div class="table-scroll" role="region" tabindex="0" aria-label="系统配置列表"><table><caption class="sr-only">系统配置列表</caption><thead><tr><th scope="col">名称</th><th scope="col">键</th><th scope="col">值</th><th scope="col">允许修改</th><th scope="col">备注</th><th scope="col">操作</th></tr></thead><tbody>
        <%= for config <- @config_rows do %>
          <tr><td><%= config["configName"] %></td><td><%= config["configKey"] %></td><td><%= config["configValue"] %></td><td><%= config["isAllowChangeStr"] || if(config["isAllowChange"] == 1, do: "是", else: "否") %></td><td><%= config["remark"] || "" %></td><td :if={!@read_only}><button type="button" class="refresh" phx-click="edit-config" phx-value-config-id={config["configId"]} phx-disable-with="加载中…">编辑</button></td></tr>
        <% end %>
      </tbody></table></div>
    </div>
    """
  end

  def dicts(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:dict_data_page_num, fn -> 1 end)
      |> assign_new(:dict_data_page_size, fn -> 50 end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button :if={!@read_only} type="button" class="refresh" phx-click="new-dict-type" phx-disable-with="处理中…">新建字典类型</button><button type="button" class="refresh secondary" phx-click="refresh-dicts" phx-disable-with="刷新中…">刷新字典</button></div>
      <%= if @dict_feedback do %><p id="dict-feedback" class={Feedback.class(@dict_feedback)} role={Feedback.role(@dict_feedback)} aria-live={Feedback.live(@dict_feedback)}><%= Feedback.message(@dict_feedback) %></p><% end %>
      <p :if={@dict_type_rows == [] and @dict_data_rows == []} class="table-empty" role="status">暂无字典数据</p>
      <h3>字典类型</h3>
      <form :if={!@read_only} aria-describedby="dict-feedback" phx-submit="save-dict-type">
        <input type="hidden" name="dictId" value={@dict_type_form["dictId"]} />
        <div class="form-grid">
          <div><label for="dict-name">字典名称</label><input id="dict-name" name="dictName" value={@dict_type_form["dictName"] || ""} required /></div>
          <div><label for="dict-type">字典类型</label><input id="dict-type" name="dictType" value={@dict_type_form["dictType"] || ""} required /></div>
          <div><label for="dict-status">状态</label><select id="dict-status" name="status"><option value="1" selected={@dict_type_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@dict_type_form["status"] in [0, "0"]}>停用</option></select></div>
          <div><label for="dict-remark">备注</label><input id="dict-remark" name="remark" value={@dict_type_form["remark"] || ""} /></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存字典类型</button><button :if={@dict_type_form["dictId"] != ""} type="button" class="secondary" phx-click="new-dict-type" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
      <div class="table-scroll" role="region" tabindex="0" aria-label="字典类型列表"><table><caption class="sr-only">字典类型列表</caption><thead><tr><th scope="col">名称</th><th scope="col">类型</th><th scope="col">状态</th><th scope="col">备注</th><th scope="col">操作</th></tr></thead><tbody>
        <%= for dict <- @dict_type_rows do %>
          <tr><td><%= dict["dictName"] %></td><td><%= dict["dictType"] %></td><td><span class={"status-badge #{Status.normal_paused(dict["status"])}"}><%= if dict["status"] == 1, do: "正常", else: "停用" %></span></td><td><%= dict["remark"] || "" %></td><td class="table-actions"><button type="button" class="refresh" phx-click="select-dict-type" phx-value-dict-type={dict["dictType"]} phx-disable-with="加载中…">查看数据</button><button :if={!@read_only} type="button" class="refresh" phx-click="edit-dict-type" phx-value-dict-id={dict["dictId"]} phx-disable-with="加载中…">编辑</button><button :if={!@read_only} type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-dict-type" phx-value-dict-id={dict["dictId"]} phx-disable-with="删除中…">删除</button></td></tr>
        <% end %>
      </tbody></table></div>
      <h3>字典数据（<%= @selected_dict_type || "未选择" %>）</h3>
      <div class="form-actions"><button :if={!@read_only} type="button" class="refresh" phx-click="new-dict-data" phx-disable-with="处理中…">新建字典数据</button></div>
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
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存字典数据</button><button :if={@dict_data_form["dictCode"] != ""} type="button" class="secondary" phx-click="new-dict-data" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
      <div class="table-scroll" role="region" tabindex="0" aria-label="字典数据列表"><table><caption class="sr-only">字典数据列表</caption><thead><tr><th scope="col">标签</th><th scope="col">值</th><th scope="col">排序</th><th scope="col">默认</th><th scope="col">状态</th><th scope="col">操作</th></tr></thead><tbody>
          <%= for data <- page_rows(@dict_data_rows, @dict_data_page_num, @dict_data_page_size) do %>
          <tr><td><%= data["dictLabel"] %></td><td><%= data["dictValue"] %></td><td><%= data["dictSort"] %></td><td><%= if data["isDefault"] == 1, do: "是", else: "否" %></td><td><span class={"status-badge #{Status.normal_paused(data["status"])}"}><%= if data["status"] == 1, do: "正常", else: "停用" %></span></td><td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="edit-dict-data" phx-value-dict-code={data["dictCode"]} phx-disable-with="加载中…">编辑</button><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-dict-data" phx-value-dict-code={data["dictCode"]} phx-disable-with="删除中…">删除</button></td></tr>
        <% end %>
      </tbody></table></div>
      <.pagination panel="dict-data" page_num={min(@dict_data_page_num, page_count(length(@dict_data_rows), @dict_data_page_size))} page_size={@dict_data_page_size} total={length(@dict_data_rows)} />
    </div>
    """
  end

  def notices(assigns) do
    assigns = assign_new(assigns, :read_only, fn -> false end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button type="button" class="refresh" phx-click="refresh-notices" phx-disable-with="刷新中…">刷新公告</button></div>
      <%= if @notice_feedback do %><p id="notice-feedback" class={Feedback.class(@notice_feedback)} role={Feedback.role(@notice_feedback)} aria-live={Feedback.live(@notice_feedback)}><%= Feedback.message(@notice_feedback) %></p><% end %>
      <p :if={@notice_rows == []} class="table-empty" role="status">暂无公告数据</p>
      <form :if={!@read_only} aria-describedby="notice-feedback" phx-submit="save-notice">
        <input type="hidden" name="noticeId" value={@notice_form["noticeId"]} />
        <div class="form-grid">
          <div><label for="notice-title">标题</label><input id="notice-title" name="noticeTitle" value={@notice_form["noticeTitle"] || ""} required /></div>
          <div><label for="notice-type">类型</label><select id="notice-type" name="noticeType"><option value="1" selected={@notice_form["noticeType"] in [1, "1"]}>通知</option><option value="2" selected={@notice_form["noticeType"] in [2, "2"]}>公告</option></select></div>
          <div class="wide"><label for="notice-content">内容</label><textarea id="notice-content" name="noticeContent" required><%= @notice_form["noticeContent"] || "" %></textarea></div>
          <div><label for="notice-status">状态</label><select id="notice-status" name="status"><option value="1" selected={@notice_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@notice_form["status"] in [0, "0"]}>停用</option></select></div>
          <div><label for="notice-remark">备注</label><input id="notice-remark" name="remark" value={@notice_form["remark"] || ""} /></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存公告</button><button :if={@notice_form["noticeId"] != ""} type="button" class="secondary" phx-click="cancel-notice" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
      <div class="table-scroll" role="region" tabindex="0" aria-label="公告列表"><table><caption class="sr-only">公告列表</caption><thead><tr><th scope="col">标题</th><th scope="col">类型</th><th scope="col">内容</th><th scope="col">状态</th><th scope="col">备注</th><th scope="col">创建时间</th><th scope="col">操作</th></tr></thead><tbody>
        <%= for notice <- @notice_rows do %>
          <tr><td><%= notice["noticeTitle"] %></td><td><%= if notice["noticeType"] == 1, do: "通知", else: "公告" %></td><td><%= notice["noticeContent"] %></td><td><span class={"status-badge #{Status.normal_paused(notice["status"])}"}><%= if notice["status"] == 1, do: "正常", else: "停用" %></span></td><td><%= notice["remark"] || "" %></td><td><%= notice["createTime"] || "" %></td><td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="edit-notice" phx-value-notice-id={notice["noticeId"]} phx-disable-with="加载中…">编辑</button><button type="button" class="refresh" phx-click="toggle-notice-status" phx-value-notice-id={notice["noticeId"]} phx-value-status={if notice["status"] == 1, do: 0, else: 1} phx-disable-with="处理中…"><%= if notice["status"] == 1, do: "停用", else: "启用" %></button><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-notice" phx-value-notice-id={notice["noticeId"]} phx-disable-with="删除中…">删除</button></td></tr>
        <% end %>
      </tbody></table></div>
    </div>
    """
  end

  def logs(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:login_page_num, fn -> 1 end)
      |> assign_new(:operation_page_num, fn -> 1 end)
      |> assign_new(:page_size, fn -> 50 end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button type="button" class="refresh" phx-click="refresh-logs" phx-disable-with="刷新中…">刷新日志</button></div>
      <%= if @log_feedback do %><p id="log-feedback" class={Feedback.class(@log_feedback)} role={Feedback.role(@log_feedback)} aria-live={Feedback.live(@log_feedback)}><%= Feedback.message(@log_feedback) %></p><% end %>
      <p :if={@login_log_rows == [] and @operation_log_rows == []} class="table-empty" role="status">暂无日志数据</p>
      <h3>登录日志（<%= length(@login_log_rows) %>）</h3>
      <div class="table-scroll" role="region" tabindex="0" aria-label="登录日志列表"><table><caption class="sr-only">登录日志列表</caption><thead><tr><th scope="col">用户</th><th scope="col">IP</th><th scope="col">浏览器</th><th scope="col">状态</th><th scope="col">消息</th><th scope="col">时间</th><th scope="col">操作</th></tr></thead><tbody>
          <%= for log <- page_rows(@login_log_rows, @login_page_num, @page_size) do %>
          <tr><td><%= log["username"] %></td><td><%= log["ipAddress"] %></td><td><%= log["browser"] %></td><td><span class={"status-badge #{Status.success_failure(log["status"])}"}><%= if log["status"] == 1, do: "成功", else: "失败" %></span></td><td><%= log["msg"] %></td><td><%= log["loginTime"] %></td><td :if={!@read_only}><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-login-log" phx-value-log-id={log["infoId"] || log["id"]} phx-disable-with="删除中…">删除</button></td></tr>
        <% end %>
      </tbody></table></div>
      <.pagination panel="login-logs" page_num={min(@login_page_num, page_count(length(@login_log_rows), @page_size))} page_size={@page_size} total={length(@login_log_rows)} />
      <h3>操作日志（<%= length(@operation_log_rows) %>）</h3>
      <div class="table-scroll" role="region" tabindex="0" aria-label="操作日志列表"><table><caption class="sr-only">操作日志列表</caption><thead><tr><th scope="col">用户</th><th scope="col">模块</th><th scope="col">方法</th><th scope="col">请求地址</th><th scope="col">状态</th><th scope="col">时间</th><th scope="col">操作</th></tr></thead><tbody>
          <%= for log <- page_rows(@operation_log_rows, @operation_page_num, @page_size) do %>
          <tr><td><%= log["username"] %></td><td><%= log["requestModule"] %></td><td><%= log["requestMethod"] %></td><td><%= log["requestUrl"] %></td><td><span class={"status-badge #{Status.success_failure(log["status"])}"}><%= if log["status"] == 1, do: "成功", else: "失败" %></span></td><td><%= log["operationTime"] %></td><td :if={!@read_only}><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-operation-log" phx-value-log-id={log["operationId"]} phx-disable-with="删除中…">删除</button></td></tr>
        <% end %>
      </tbody></table></div>
      <.pagination panel="operation-logs" page_num={min(@operation_page_num, page_count(length(@operation_log_rows), @page_size))} page_size={@page_size} total={length(@operation_log_rows)} />
    </div>
    """
  end
end
