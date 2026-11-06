defmodule KeystonePhoenixWeb.Live.AdminPages.Operations do
  @moduledoc "LiveView panels for scheduled jobs, job logs, and runtime monitoring."

  use Phoenix.Component

  def jobs(assigns) do
    assigns = assign_new(assigns, :read_only, fn -> false end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button :if={!@read_only} type="button" class="refresh" phx-click="new-job">新建任务</button><button type="button" class="refresh secondary" phx-click="refresh-jobs">刷新任务</button></div>
      <%= if @job_feedback do %><p class="feedback" role="status"><%= @job_feedback %></p><% end %>
      <form :if={!@read_only} phx-submit="save-job">
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
        <div class="form-actions"><button type="submit">保存任务</button><button :if={@job_form["jobId"] != ""} type="button" class="secondary" phx-click="new-job">取消编辑</button></div>
      </form>
      <table><thead><tr><th>任务名称</th><th>分组</th><th>调用目标</th><th>Cron</th><th>并发</th><th>状态</th><th>操作</th></tr></thead><tbody>
        <%= for job <- @job_rows do %>
          <tr><td><%= job["jobName"] %></td><td><%= job["jobGroup"] %></td><td><%= job["invokeTarget"] %></td><td><%= job["cronExpression"] %></td><td><%= if job["concurrent"] in [1, "1"], do: "是", else: "否" %></td><td><%= job["statusStr"] || if(job["status"] == 1, do: "正常", else: "暂停") %></td><td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="edit-job" phx-value-job-id={job["jobId"]}>编辑</button><button type="button" class="refresh" phx-click="run-job" phx-value-job-id={job["jobId"]}>立即执行</button><button type="button" class="refresh secondary" phx-click="cancel-job" phx-value-job-id={job["jobId"]}>取消执行</button><button type="button" class="refresh" phx-click="toggle-job-status" phx-value-job-id={job["jobId"]} phx-value-status={if job["status"] == 1, do: 0, else: 1}><%= if job["status"] == 1, do: "暂停", else: "启用" %></button><button type="button" class="refresh danger-action" phx-click="delete-job" phx-value-job-id={job["jobId"]}>删除</button></td></tr>
        <% end %>
      </tbody></table>
    </div>
    """
  end

  def job_logs(assigns) do
    assigns = assign_new(assigns, :read_only, fn -> false end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button type="button" class="refresh" phx-click="refresh-job-logs">刷新任务日志</button></div>
      <%= if @job_log_feedback do %><p class="feedback" role="status"><%= @job_log_feedback %></p><% end %>
      <table><thead><tr><th>任务</th><th>分组</th><th>调用目标</th><th>状态</th><th>消息</th><th>开始时间</th><th>结束时间</th></tr></thead><tbody>
        <%= for log <- @job_log_rows do %>
          <tr><td><%= log["jobName"] %></td><td><%= log["jobGroup"] %></td><td><%= log["invokeTarget"] %></td><td><%= log["statusStr"] || if(log["status"] == 1, do: "成功", else: "失败") %></td><td><%= log["jobMessage"] || log["exceptionInfo"] || "" %></td><td><%= log["startTime"] || "" %></td><td><%= log["stopTime"] || "" %></td></tr>
        <% end %>
      </tbody></table>
    </div>
    """
  end

  def monitor(assigns) do
    assigns = assign_new(assigns, :read_only, fn -> false end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button type="button" class="refresh" phx-click="refresh-monitor">刷新监控</button></div>
      <%= if @monitor_feedback do %><p class="feedback" role="status"><%= @monitor_feedback %></p><% end %>
      <div class="monitor-grid">
        <div class="metric"><span>CPU 使用率</span><strong><%= get_in(@monitor_server_info, ["cpuInfo", "used"]) || 0 %>%</strong><small>逻辑处理器：<%= get_in(@monitor_server_info, ["cpuInfo", "cpuNum"]) || 0 %></small></div>
        <div class="metric"><span>主机内存</span><strong><%= get_in(@monitor_server_info, ["memoryInfo", "usage"]) || 0 %>%</strong><small><%= get_in(@monitor_server_info, ["memoryInfo", "used"]) || 0 %> / <%= get_in(@monitor_server_info, ["memoryInfo", "total"]) || 0 %> GB</small></div>
        <div class="metric"><span>BEAM 内存</span><strong><%= get_in(@monitor_server_info, ["jvmInfo", "usage"]) || 0 %>%</strong><small><%= get_in(@monitor_server_info, ["jvmInfo", "used"]) || 0 %> / <%= get_in(@monitor_server_info, ["jvmInfo", "max"]) || 0 %> MB</small></div>
        <div class="metric"><span>网络状态</span><strong><%= @network_status["status"] || "UNKNOWN" %></strong><small><%= @network_status["checkedAt"] || "未检查" %></small></div>
      </div>
      <div class="monitor-grid details">
        <div><h3>运行环境</h3><p>节点：<%= get_in(@monitor_server_info, ["systemInfo", "computerName"]) || "未知" %></p><p>系统：<%= get_in(@monitor_server_info, ["systemInfo", "osName"]) || "未知" %></p><p>BEAM：<%= get_in(@monitor_server_info, ["jvmInfo", "name"]) || "未知" %></p><p>运行时间：<%= get_in(@monitor_server_info, ["jvmInfo", "runTime"]) || "未知" %></p></div>
        <div><h3>ETS 缓存</h3><p>后端：<%= @monitor_cache_info["backend"] || "不可用" %></p><p>缓存条目：<%= @monitor_cache_info["cacheEntries"] || 0 %></p><p>验证码条目：<%= @monitor_cache_info["captchaEntries"] || 0 %></p></div>
      </div>
      <h3>在线会话（<%= length(@online_user_rows) %>）</h3>
      <table><thead><tr><th>用户</th><th>部门</th><th>IP</th><th>登录时间</th><th>操作</th></tr></thead><tbody>
        <%= for user <- @online_user_rows do %>
          <tr><td><%= user["username"] %></td><td><%= user["deptName"] || "" %></td><td><%= user["ipAddress"] %></td><td><%= user["loginTime"] %></td><td :if={!@read_only}><button type="button" class="refresh danger-action" phx-click="logout-online-user" phx-value-token-id={user["tokenId"]}>强制下线</button></td></tr>
        <% end %>
      </tbody></table>
    </div>
    """
  end
end
