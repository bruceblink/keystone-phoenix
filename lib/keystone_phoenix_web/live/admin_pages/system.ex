defmodule KeystonePhoenixWeb.Live.AdminPages.System do
  @moduledoc "LiveView panels for system configuration, dictionaries, notices, and logs."

  use Phoenix.Component

  def configs(assigns) do
    assigns = assign_new(assigns, :read_only, fn -> false end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button :if={!@read_only} type="button" class="refresh" phx-click="new-config">新建配置</button><button type="button" class="refresh secondary" phx-click="refresh-config">刷新配置</button></div>
      <%= if @config_feedback do %><p class="feedback" role="status"><%= @config_feedback %></p><% end %>
      <form :if={!@read_only} phx-submit="save-config">
        <input type="hidden" name="configId" value={@config_form["configId"]} />
        <div class="form-grid">
          <div><label for="config-name">配置名称</label><input id="config-name" name="configName" value={@config_form["configName"] || ""} required /></div>
          <div><label for="config-key">配置键</label><input id="config-key" name="configKey" value={@config_form["configKey"] || ""} required /></div>
          <div><label for="config-value">配置值</label><input id="config-value" name="configValue" value={@config_form["configValue"] || ""} required /></div>
          <div><label for="config-options">可选值（逗号分隔）</label><input id="config-options" name="configOptions" value={@config_form["configOptions"] || ""} /></div>
          <div><label for="config-change">允许修改</label><select id="config-change" name="isAllowChange"><option value="true" selected={@config_form["isAllowChange"] in [true, "true", 1, "1"]}>是</option><option value="false" selected={@config_form["isAllowChange"] in [false, "false", 0, "0"]}>否</option></select></div>
          <div class="wide"><label for="config-remark">备注</label><textarea id="config-remark" name="remark"><%= @config_form["remark"] || "" %></textarea></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存配置</button><button :if={@config_form["configId"] != ""} type="button" class="secondary" phx-click="new-config">取消编辑</button></div>
      </form>
      <table><thead><tr><th>名称</th><th>键</th><th>值</th><th>允许修改</th><th>备注</th><th>操作</th></tr></thead><tbody>
        <%= for config <- @config_rows do %>
          <tr><td><%= config["configName"] %></td><td><%= config["configKey"] %></td><td><%= config["configValue"] %></td><td><%= config["isAllowChangeStr"] || if(config["isAllowChange"] == 1, do: "是", else: "否") %></td><td><%= config["remark"] || "" %></td><td :if={!@read_only}><button type="button" class="refresh" phx-click="edit-config" phx-value-config-id={config["configId"]}>编辑</button></td></tr>
        <% end %>
      </tbody></table>
    </div>
    """
  end

  def dicts(assigns) do
    assigns = assign_new(assigns, :read_only, fn -> false end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button :if={!@read_only} type="button" class="refresh" phx-click="new-dict-type">新建字典类型</button><button type="button" class="refresh secondary" phx-click="refresh-dicts">刷新字典</button></div>
      <%= if @dict_feedback do %><p class="feedback" role="status"><%= @dict_feedback %></p><% end %>
      <h3>字典类型</h3>
      <form :if={!@read_only} phx-submit="save-dict-type">
        <input type="hidden" name="dictId" value={@dict_type_form["dictId"]} />
        <div class="form-grid">
          <div><label for="dict-name">字典名称</label><input id="dict-name" name="dictName" value={@dict_type_form["dictName"] || ""} required /></div>
          <div><label for="dict-type">字典类型</label><input id="dict-type" name="dictType" value={@dict_type_form["dictType"] || ""} required /></div>
          <div><label for="dict-status">状态</label><select id="dict-status" name="status"><option value="1" selected={@dict_type_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@dict_type_form["status"] in [0, "0"]}>停用</option></select></div>
          <div><label for="dict-remark">备注</label><input id="dict-remark" name="remark" value={@dict_type_form["remark"] || ""} /></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存字典类型</button><button :if={@dict_type_form["dictId"] != ""} type="button" class="secondary" phx-click="new-dict-type">取消编辑</button></div>
      </form>
      <table><thead><tr><th>名称</th><th>类型</th><th>状态</th><th>备注</th><th>操作</th></tr></thead><tbody>
        <%= for dict <- @dict_type_rows do %>
          <tr><td><%= dict["dictName"] %></td><td><%= dict["dictType"] %></td><td><%= if dict["status"] == 1, do: "正常", else: "停用" %></td><td><%= dict["remark"] || "" %></td><td class="table-actions"><button type="button" class="refresh" phx-click="select-dict-type" phx-value-dict-type={dict["dictType"]}>查看数据</button><button :if={!@read_only} type="button" class="refresh" phx-click="edit-dict-type" phx-value-dict-id={dict["dictId"]}>编辑</button><button :if={!@read_only} type="button" class="refresh danger-action" phx-click="delete-dict-type" phx-value-dict-id={dict["dictId"]}>删除</button></td></tr>
        <% end %>
      </tbody></table>
      <h3>字典数据（<%= @selected_dict_type || "未选择" %>）</h3>
      <div class="form-actions"><button :if={!@read_only} type="button" class="refresh" phx-click="new-dict-data">新建字典数据</button></div>
      <form :if={!@read_only} phx-submit="save-dict-data">
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
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存字典数据</button><button :if={@dict_data_form["dictCode"] != ""} type="button" class="secondary" phx-click="new-dict-data">取消编辑</button></div>
      </form>
      <table><thead><tr><th>标签</th><th>值</th><th>排序</th><th>默认</th><th>状态</th><th>操作</th></tr></thead><tbody>
        <%= for data <- @dict_data_rows do %>
          <tr><td><%= data["dictLabel"] %></td><td><%= data["dictValue"] %></td><td><%= data["dictSort"] %></td><td><%= if data["isDefault"] == 1, do: "是", else: "否" %></td><td><%= if data["status"] == 1, do: "正常", else: "停用" %></td><td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="edit-dict-data" phx-value-dict-code={data["dictCode"]}>编辑</button><button type="button" class="refresh danger-action" phx-click="delete-dict-data" phx-value-dict-code={data["dictCode"]}>删除</button></td></tr>
        <% end %>
      </tbody></table>
    </div>
    """
  end

  def notices(assigns) do
    assigns = assign_new(assigns, :read_only, fn -> false end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button type="button" class="refresh" phx-click="refresh-notices">刷新公告</button></div>
      <%= if @notice_feedback do %><p class="feedback" role="status"><%= @notice_feedback %></p><% end %>
      <form :if={!@read_only} phx-submit="save-notice">
        <input type="hidden" name="noticeId" value={@notice_form["noticeId"]} />
        <div class="form-grid">
          <div><label for="notice-title">标题</label><input id="notice-title" name="noticeTitle" value={@notice_form["noticeTitle"] || ""} required /></div>
          <div><label for="notice-type">类型</label><select id="notice-type" name="noticeType"><option value="1" selected={@notice_form["noticeType"] in [1, "1"]}>通知</option><option value="2" selected={@notice_form["noticeType"] in [2, "2"]}>公告</option></select></div>
          <div class="wide"><label for="notice-content">内容</label><textarea id="notice-content" name="noticeContent" required><%= @notice_form["noticeContent"] || "" %></textarea></div>
          <div><label for="notice-status">状态</label><select id="notice-status" name="status"><option value="1" selected={@notice_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@notice_form["status"] in [0, "0"]}>停用</option></select></div>
          <div><label for="notice-remark">备注</label><input id="notice-remark" name="remark" value={@notice_form["remark"] || ""} /></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存公告</button><button :if={@notice_form["noticeId"] != ""} type="button" class="secondary" phx-click="cancel-notice">取消编辑</button></div>
      </form>
      <table><thead><tr><th>标题</th><th>类型</th><th>内容</th><th>状态</th><th>备注</th><th>创建时间</th><th>操作</th></tr></thead><tbody>
        <%= for notice <- @notice_rows do %>
          <tr><td><%= notice["noticeTitle"] %></td><td><%= if notice["noticeType"] == 1, do: "通知", else: "公告" %></td><td><%= notice["noticeContent"] %></td><td><%= if notice["status"] == 1, do: "正常", else: "停用" %></td><td><%= notice["remark"] || "" %></td><td><%= notice["createTime"] || "" %></td><td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="edit-notice" phx-value-notice-id={notice["noticeId"]}>编辑</button><button type="button" class="refresh" phx-click="toggle-notice-status" phx-value-notice-id={notice["noticeId"]} phx-value-status={if notice["status"] == 1, do: 0, else: 1}><%= if notice["status"] == 1, do: "停用", else: "启用" %></button><button type="button" class="refresh danger-action" phx-click="delete-notice" phx-value-notice-id={notice["noticeId"]}>删除</button></td></tr>
        <% end %>
      </tbody></table>
    </div>
    """
  end

  def logs(assigns) do
    assigns = assign_new(assigns, :read_only, fn -> false end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button type="button" class="refresh" phx-click="refresh-logs">刷新日志</button></div>
      <%= if @log_feedback do %><p class="feedback" role="status"><%= @log_feedback %></p><% end %>
      <h3>登录日志（<%= length(@login_log_rows) %>）</h3>
      <table><thead><tr><th>用户</th><th>IP</th><th>浏览器</th><th>状态</th><th>消息</th><th>时间</th><th>操作</th></tr></thead><tbody>
        <%= for log <- @login_log_rows do %>
          <tr><td><%= log["username"] %></td><td><%= log["ipAddress"] %></td><td><%= log["browser"] %></td><td><%= if log["status"] == 1, do: "成功", else: "失败" %></td><td><%= log["msg"] %></td><td><%= log["loginTime"] %></td><td :if={!@read_only}><button type="button" class="refresh danger-action" phx-click="delete-login-log" phx-value-log-id={log["infoId"] || log["id"]}>删除</button></td></tr>
        <% end %>
      </tbody></table>
      <h3>操作日志（<%= length(@operation_log_rows) %>）</h3>
      <table><thead><tr><th>用户</th><th>模块</th><th>方法</th><th>请求地址</th><th>状态</th><th>时间</th><th>操作</th></tr></thead><tbody>
        <%= for log <- @operation_log_rows do %>
          <tr><td><%= log["username"] %></td><td><%= log["requestModule"] %></td><td><%= log["requestMethod"] %></td><td><%= log["requestUrl"] %></td><td><%= if log["status"] == 1, do: "成功", else: "失败" %></td><td><%= log["operationTime"] %></td><td :if={!@read_only}><button type="button" class="refresh danger-action" phx-click="delete-operation-log" phx-value-log-id={log["operationId"]}>删除</button></td></tr>
        <% end %>
      </tbody></table>
    </div>
    """
  end
end
