defmodule KeystonePhoenixWeb.Live.AdminPages.Operations do
  @moduledoc "LiveView panels for scheduled jobs, job logs, and runtime monitoring."

  use Phoenix.Component

  import KeystonePhoenixWeb.Live.AdminPages.Pagination
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def jobs(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:page_num, fn -> 1 end)
      |> assign_new(:page_size, fn -> 50 end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button :if={!@read_only} type="button" class="refresh" phx-click="new-job" phx-disable-with="处理中…">新建任务</button><button type="button" class="refresh secondary" phx-click="refresh-jobs" phx-disable-with="刷新中…">刷新任务</button></div>
      <%= if @job_feedback do %><p id="job-feedback" class="feedback" role="status" aria-live="polite"><%= @job_feedback %></p><% end %>
      <p :if={@job_rows == []} class="table-empty" role="status">暂无定时任务</p>
      <form :if={!@read_only} aria-describedby="job-feedback" phx-submit="save-job">
        <input type="hidden" name="jobId" value={@job_form["jobId"]} />
        <div class="form-grid">
          <div><label for="job-name">任务名称</label><input id="job-name" name="jobName" value={@job_form["jobName"] || ""} required /></div>
          <div><label for="job-group">任务分组</label><input id="job-group" name="jobGroup" value={@job_form["jobGroup"] || "DEFAULT"} /></div>
          <div><label for="job-target">调用目标</label><input id="job-target" name="invokeTarget" list="job-targets" value={@job_form["invokeTarget"] || ""} required /><datalist id="job-targets"><%= for target <- @job_targets do %><option value={target["invokeTarget"] || ""}><%= target["name"] || target["invokeTarget"] || "" %></option><% end %></datalist></div>
          <div><label for="job-cron">Cron 表达式</label><input id="job-cron" name="cronExpression" value={@job_form["cronExpression"] || ""} required /></div>
          <div><label for="job-params">调用参数</label><input id="job-params" name="jobParams" value={@job_form["jobParams"] || ""} /></div>
          <div><label for="job-concurrent">允许并发</label><select id="job-concurrent" name="concurrent"><option value="0" selected={@job_form["concurrent"] in [0, "0"]}>否</option><option value="1" selected={@job_form["concurrent"] in [1, "1"]}>是</option></select></div>
          <div><label for="job-status">状态</label><select id="job-status" name="status"><option value="1" selected={@job_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@job_form["status"] in [0, "0"]}>暂停</option></select></div>
          <div class="wide"><label for="job-remark">备注</label><textarea id="job-remark" name="remark"><%= @job_form["remark"] || "" %></textarea></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存任务</button><button :if={@job_form["jobId"] != ""} type="button" class="secondary" phx-click="new-job" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
      <div class="table-scroll" role="region" tabindex="0" aria-label="定时任务列表"><table><caption class="sr-only">定时任务列表</caption><thead><tr><th>任务名称</th><th>分组</th><th>调用目标</th><th>Cron</th><th>并发</th><th>状态</th><th>操作</th></tr></thead><tbody>
        <%= for job <- Support.page_rows(@job_rows, @page_num, @page_size) do %>
          <tr><td><%= job["jobName"] %></td><td><%= job["jobGroup"] %></td><td><%= job["invokeTarget"] %></td><td><%= job["cronExpression"] %></td><td><%= if job["concurrent"] in [1, "1"], do: "是", else: "否" %></td><td><span class={"status-badge #{job_status_badge_class(job["status"])}"}><%= job["statusStr"] || if(job["status"] == 1, do: "正常", else: "暂停") %></span></td><td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="edit-job" phx-value-job-id={job["jobId"]} phx-disable-with="加载中…">编辑</button><button type="button" class="refresh" phx-click="run-job" phx-value-job-id={job["jobId"]} phx-disable-with="执行中…">立即执行</button><button type="button" class="refresh secondary" phx-click="cancel-job" phx-value-job-id={job["jobId"]} phx-disable-with="处理中…">取消执行</button><button type="button" class="refresh" phx-click="toggle-job-status" phx-value-job-id={job["jobId"]} phx-value-status={if job["status"] == 1, do: 0, else: 1} phx-disable-with="处理中…"><%= if job["status"] == 1, do: "暂停", else: "启用" %></button><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-job" phx-value-job-id={job["jobId"]} phx-disable-with="删除中…">删除</button></td></tr>
        <% end %>
      </tbody></table></div>
      <.pagination panel="jobs" page_num={min(@page_num, page_count(length(@job_rows), @page_size))} page_size={@page_size} total={length(@job_rows)} />
    </div>
    """
  end

  def job_logs(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:page_num, fn -> 1 end)
      |> assign_new(:page_size, fn -> 50 end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button type="button" class="refresh" phx-click="refresh-job-logs" phx-disable-with="刷新中…">刷新任务日志</button></div>
      <%= if @job_log_feedback do %><p id="job-log-feedback" class="feedback" role="status" aria-live="polite"><%= @job_log_feedback %></p><% end %>
      <p :if={@job_log_rows == []} class="table-empty" role="status">暂无任务日志</p>
      <div class="table-scroll" role="region" tabindex="0" aria-label="任务日志列表"><table><caption class="sr-only">任务日志列表</caption><thead><tr><th>任务</th><th>分组</th><th>调用目标</th><th>状态</th><th>消息</th><th>开始时间</th><th>结束时间</th></tr></thead><tbody>
        <%= for log <- Support.page_rows(@job_log_rows, @page_num, @page_size) do %>
          <tr><td><%= log["jobName"] %></td><td><%= log["jobGroup"] %></td><td><%= log["invokeTarget"] %></td><td><span class={"status-badge #{job_log_status_badge_class(log["status"])}"}><%= log["statusStr"] || if(log["status"] == 1, do: "成功", else: "失败") %></span></td><td><%= log["jobMessage"] || log["exceptionInfo"] || "" %></td><td><%= log["startTime"] || "" %></td><td><%= log["endTime"] || "" %></td></tr>
        <% end %>
      </tbody></table></div>
      <.pagination panel="job-logs" page_num={min(@page_num, page_count(length(@job_log_rows), @page_size))} page_size={@page_size} total={length(@job_log_rows)} />
    </div>
    """
  end

  def monitor(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:online_user_page_num, fn -> 1 end)
      |> assign_new(:online_user_page_size, fn -> 50 end)
      |> assign_new(:online_user_total, fn -> length(assigns[:online_user_rows] || []) end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button type="button" class="refresh" phx-click="refresh-monitor" phx-disable-with="刷新中…">刷新监控</button></div>
      <%= if @monitor_feedback do %><p id="monitor-feedback" class="feedback" role="status" aria-live="polite"><%= @monitor_feedback %></p><% end %>
      <p :if={@online_user_rows == []} class="table-empty" role="status">暂无在线会话</p>
      <div class="monitor-grid">
        <div class="metric"><span>CPU 使用率</span><strong><%= get_in(@monitor_server_info, ["cpuInfo", "used"]) || 0 %>%</strong><small>逻辑处理器：<%= get_in(@monitor_server_info, ["cpuInfo", "cpuNum"]) || 0 %></small></div>
        <div class="metric"><span>主机内存</span><strong><%= get_in(@monitor_server_info, ["memoryInfo", "usage"]) || 0 %>%</strong><small><%= get_in(@monitor_server_info, ["memoryInfo", "used"]) || 0 %> / <%= get_in(@monitor_server_info, ["memoryInfo", "total"]) || 0 %> GB</small></div>
        <div class="metric"><span>BEAM 内存</span><strong><%= get_in(@monitor_server_info, ["jvmInfo", "usage"]) || 0 %>%</strong><small><%= get_in(@monitor_server_info, ["jvmInfo", "used"]) || 0 %> / <%= get_in(@monitor_server_info, ["jvmInfo", "max"]) || 0 %> MB</small></div>
        <div class="metric"><span>网络状态</span><strong><span class={"status-badge #{network_status_badge_class(@network_status["status"])}"}><%= @network_status["status"] || "UNKNOWN" %></span></strong><small><%= @network_status["checkedAt"] || "未检查" %></small></div>
      </div>
      <div class="monitor-grid details">
        <div><h3>运行环境</h3><p>节点：<%= get_in(@monitor_server_info, ["systemInfo", "computerName"]) || "未知" %></p><p>系统：<%= get_in(@monitor_server_info, ["systemInfo", "osName"]) || "未知" %></p><p>BEAM：<%= get_in(@monitor_server_info, ["jvmInfo", "name"]) || "未知" %></p><p>运行时间：<%= get_in(@monitor_server_info, ["jvmInfo", "runTime"]) || "未知" %></p></div>
        <div><h3>ETS 缓存</h3><p>后端：<%= @monitor_cache_info["backend"] || "不可用" %></p><p>缓存条目：<%= @monitor_cache_info["cacheEntries"] || 0 %></p><p>验证码条目：<%= @monitor_cache_info["captchaEntries"] || 0 %></p></div>
      </div>
      <h3>在线会话（<%= @online_user_total %>）</h3>
      <div class="table-scroll" role="region" tabindex="0" aria-label="在线会话列表"><table><caption class="sr-only">在线会话列表</caption><thead><tr><th>用户</th><th>部门</th><th>IP</th><th>登录时间</th><th>操作</th></tr></thead><tbody>
        <%= for user <- @online_user_rows do %>
          <tr><td><%= user["username"] %></td><td><%= user["deptName"] || "" %></td><td><%= user["ipAddress"] %></td><td><%= user["loginTime"] %></td><td :if={!@read_only}><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="logout-online-user" phx-value-token-id={user["tokenId"]} phx-disable-with="下线中…">强制下线</button></td></tr>
        <% end %>
      </tbody></table></div>
      <.pagination panel="online-users" page_num={@online_user_page_num} page_size={@online_user_page_size} total={@online_user_total} />
    </div>
    """
  end

  # 将定时任务状态值映射为稳定的视觉语义，状态文本仍由数据字段提供。
  defp job_status_badge_class(1), do: "status-badge--normal"
  defp job_status_badge_class(_status), do: "status-badge--paused"

  # 按 Job 模块的状态值映射日志徽标，未知值保留可辨识的中性样式。
  defp job_log_status_badge_class(0), do: "status-badge--failure"
  defp job_log_status_badge_class(1), do: "status-badge--success"
  defp job_log_status_badge_class(2), do: "status-badge--skipped"
  defp job_log_status_badge_class(_status), do: "status-badge--unknown"

  # 将监控接口的网络状态映射为稳定的视觉语义，未知值保留中性样式。
  defp network_status_badge_class("ONLINE"), do: "status-badge--success"
  defp network_status_badge_class("OFFLINE"), do: "status-badge--failure"
  defp network_status_badge_class(_status), do: "status-badge--unknown"
end
