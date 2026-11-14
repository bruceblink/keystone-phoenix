defmodule KeystonePhoenixWeb.Live.AdminPages.Operations do
  @moduledoc "LiveView panels for scheduled jobs, job logs, and runtime monitoring."

  use Phoenix.Component

  import KeystonePhoenixWeb.Live.AdminPages.Pagination
  import KeystonePhoenixWeb.Live.AdminPages.Modal
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminPages.Status

  def jobs(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:active_modal, fn -> nil end)
      |> assign_new(:page_num, fn -> 1 end)
      |> assign_new(:page_size, fn -> 50 end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button :if={!@read_only} type="button" class="refresh" phx-click="new-job" phx-disable-with="处理中…">新建任务</button><button type="button" class="refresh secondary" phx-click="refresh-jobs" phx-disable-with="刷新中…">刷新任务</button></div>
      <%= if @job_feedback do %><p id="job-feedback" class={Feedback.class(@job_feedback)} role={Feedback.role(@job_feedback)} aria-live={Feedback.live(@job_feedback)}><%= Feedback.message(@job_feedback) %></p><% end %>
      <p :if={@job_rows == []} class="table-empty" role="status">暂无定时任务</p>
      <%= if @active_modal == "job" do %>
        <.modal id="job-modal" title={if @job_form["jobId"] == "", do: "新建任务", else: "编辑任务"} description="维护调度目标、执行计划和运行状态。">
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
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存任务</button><button :if={@job_form["jobId"] != ""} type="button" class="secondary" phx-click="close-modal" phx-value-modal="job" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
        </.modal>
      <% end %>
      <div class="table-scroll" role="region" tabindex="0" aria-label="定时任务列表"><table><caption class="sr-only">定时任务列表</caption><thead><tr><th scope="col">任务名称</th><th scope="col">分组</th><th scope="col">调用目标</th><th scope="col">Cron</th><th scope="col">并发</th><th scope="col">状态</th><th scope="col">操作</th></tr></thead><tbody>
        <%= for job <- page_rows(@job_rows, @page_num, @page_size) do %>
          <tr><td><%= job["jobName"] %></td><td><%= job["jobGroup"] %></td><td><%= job["invokeTarget"] %></td><td><%= job["cronExpression"] %></td><td><%= if job["concurrent"] in [1, "1"], do: "是", else: "否" %></td><td><span class={"status-badge #{Status.normal_paused(job["status"])}"}><%= job["statusStr"] || if(job["status"] == 1, do: "正常", else: "暂停") %></span></td><td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="edit-job" phx-value-job-id={job["jobId"]} phx-disable-with="加载中…">编辑</button><button type="button" class="refresh" phx-click="run-job" phx-value-job-id={job["jobId"]} phx-disable-with="执行中…">立即执行</button><button type="button" class="refresh secondary" phx-click="cancel-job" phx-value-job-id={job["jobId"]} phx-disable-with="处理中…">取消执行</button><button type="button" class="refresh" phx-click="toggle-job-status" phx-value-job-id={job["jobId"]} phx-value-status={if job["status"] == 1, do: 0, else: 1} phx-disable-with="处理中…"><%= if job["status"] == 1, do: "暂停", else: "启用" %></button><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-job" phx-value-job-id={job["jobId"]} phx-disable-with="删除中…">删除</button></td></tr>
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
      <%= if @job_log_feedback do %><p id="job-log-feedback" class={Feedback.class(@job_log_feedback)} role={Feedback.role(@job_log_feedback)} aria-live={Feedback.live(@job_log_feedback)}><%= Feedback.message(@job_log_feedback) %></p><% end %>
      <p :if={@job_log_rows == []} class="table-empty" role="status">暂无任务日志</p>
      <div class="table-scroll" role="region" tabindex="0" aria-label="任务日志列表"><table><caption class="sr-only">任务日志列表</caption><thead><tr><th scope="col">任务</th><th scope="col">分组</th><th scope="col">调用目标</th><th scope="col">状态</th><th scope="col">消息</th><th scope="col">开始时间</th><th scope="col">结束时间</th></tr></thead><tbody>
        <%= for log <- page_rows(@job_log_rows, @page_num, @page_size) do %>
          <tr><td><%= log["jobName"] %></td><td><%= log["jobGroup"] %></td><td><%= log["invokeTarget"] %></td><td><span class={"status-badge #{Status.job_log(log["status"])}"}><%= log["statusStr"] || if(log["status"] == 1, do: "成功", else: "失败") %></span></td><td><%= log["jobMessage"] || log["exceptionInfo"] || "" %></td><td><%= log["startTime"] || "" %></td><td><%= log["endTime"] || "" %></td></tr>
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
    <div class="monitor-workspace">
      <header class="monitor-command-bar">
        <div>
          <p class="eyebrow">运行监控 · Monitor snapshot</p>
          <h3>平台运行状态</h3>
          <p class="monitor-caption">聚合当前节点、资源和在线会话数据，帮助你快速确认系统是否需要处理。</p>
        </div>
        <div class="monitor-command-actions">
          <span class={"monitor-live-state #{monitor_state_class(@network_status)} status-badge #{Status.network(@network_status["status"])}"} role="status">
            <span class="monitor-live-dot" aria-hidden="true"></span>
            <%= monitor_state_label(@network_status) %>
            <span class="sr-only"><%= @network_status["status"] || "UNKNOWN" %></span>
          </span>
          <time class="monitor-updated" datetime={@network_status["checkedAt"] || ""}>
            <%= @network_status["checkedAt"] || "暂无更新时间" %>
          </time>
          <button type="button" class="refresh" phx-click="refresh-monitor" phx-disable-with="刷新中…">刷新监控</button>
        </div>
      </header>

      <%= if @monitor_feedback do %>
        <p id="monitor-feedback" class={Feedback.class(@monitor_feedback)} role={Feedback.role(@monitor_feedback)} aria-live={Feedback.live(@monitor_feedback)}><%= Feedback.message(@monitor_feedback) %></p>
      <% end %>

      <div class="monitor-health-strip" aria-label="平台健康摘要">
        <div class="monitor-health-summary">
          <span class="monitor-kicker">当前判断</span>
          <strong><%= monitor_health_title(@network_status, @monitor_server_info) %></strong>
          <span><%= monitor_health_detail(@network_status, @monitor_server_info) %></span>
        </div>
        <div class="monitor-health-stat"><span>在线会话</span><strong><%= @online_user_total %></strong><small>当前登录用户</small></div>
        <div class="monitor-health-stat"><span>缓存条目</span><strong><%= @monitor_cache_info["cacheEntries"] || 0 %></strong><small><%= @monitor_cache_info["backend"] || "缓存不可用" %></small></div>
        <div class="monitor-health-stat"><span>运行时间</span><strong><%= monitor_compact_runtime(@monitor_server_info) %></strong><small>当前节点</small></div>
      </div>

      <div class="monitor-layout">
        <section class="monitor-main-column">
          <section class="monitor-chart-panel" aria-labelledby="monitor-chart-title">
            <header class="monitor-section-heading">
              <div><span class="monitor-kicker">Resource snapshot</span><h4 id="monitor-chart-title">资源使用快照</h4></div>
              <span class="monitor-window-label">当前采样 · 30 分钟窗口</span>
            </header>
            <div class="monitor-chart" role="img" aria-label={monitor_chart_label(@monitor_server_info)}>
              <svg viewBox="0 0 720 232" preserveAspectRatio="none" aria-hidden="true">
                <g class="monitor-chart-grid">
                  <line x1="176" y1="18" x2="690" y2="18" /><line x1="176" y1="67" x2="690" y2="67" /><line x1="176" y1="116" x2="690" y2="116" /><line x1="176" y1="165" x2="690" y2="165" /><line x1="176" y1="214" x2="690" y2="214" />
                  <line class="monitor-chart-threshold" x1="587" y1="8" x2="587" y2="224" />
                </g>
                <text class="monitor-chart-threshold-label" x="591" y="14">80% 阈值</text>
                <%= for {metric, index} <- Enum.with_index(monitor_metrics(@monitor_server_info)) do %>
                  <g class="monitor-chart-row">
                    <text class="monitor-chart-label" x="0" y={monitor_metric_y(index)}><%= metric.label %></text>
                    <rect class="monitor-chart-track" x="176" y={monitor_metric_bar_y(index)} width="514" height="18" rx="9" />
                    <rect class={"monitor-chart-bar #{metric.tone}"} x="176" y={monitor_metric_bar_y(index)} width={monitor_metric_width(metric.value)} height="18" rx="9" />
                    <text class="monitor-chart-value" x="700" y={monitor_metric_y(index)} text-anchor="end"><%= metric.value %>%</text>
                  </g>
                <% end %>
              </svg>
            </div>
            <div class="monitor-chart-footer"><span><i class="monitor-legend-dot monitor-legend-dot--primary"></i>当前使用率</span><span><i class="monitor-legend-line"></i>建议关注阈值</span><span class="monitor-source">来源：Monitor snapshot · 当前值来自节点采样</span></div>
          </section>

          <section class="monitor-session-panel" aria-labelledby="online-session-title">
            <header class="monitor-section-heading">
              <div><span class="monitor-kicker">Session activity</span><h4 id="online-session-title">在线会话</h4></div>
              <span class="monitor-count"><%= @online_user_total %> 个会话</span>
            </header>
            <p :if={@online_user_rows == []} class="table-empty" role="status">暂无在线会话</p>
            <div :if={@online_user_rows != []} class="table-scroll monitor-session-table" role="region" tabindex="0" aria-label="在线会话列表">
              <table><caption class="sr-only">在线会话列表</caption><thead><tr><th scope="col">用户</th><th scope="col">部门</th><th scope="col">来源地址</th><th scope="col">登录时间</th><th scope="col">操作</th></tr></thead><tbody>
                <%= for user <- @online_user_rows do %>
                  <tr><td><strong><%= user["username"] %></strong></td><td><%= user["deptName"] || "未分配部门" %></td><td><code><%= user["ipAddress"] %></code></td><td><%= user["loginTime"] %></td><td :if={!@read_only}><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="logout-online-user" phx-value-token-id={user["tokenId"]} phx-disable-with="下线中…">强制下线</button></td></tr>
                <% end %>
              </tbody></table>
            </div>
            <div :if={@online_user_rows != []} class="monitor-session-cards" aria-label="在线会话卡片">
              <article :for={user <- @online_user_rows} class="monitor-session-card">
                <div><strong><%= user["username"] %></strong><span><%= user["deptName"] || "未分配部门" %></span></div>
                <dl><div><dt>来源地址</dt><dd><%= user["ipAddress"] %></dd></div><div><dt>登录时间</dt><dd><%= user["loginTime"] %></dd></div></dl>
                <button :if={!@read_only} type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="logout-online-user" phx-value-token-id={user["tokenId"]} phx-disable-with="下线中…">强制下线</button>
              </article>
            </div>
            <.pagination panel="online-users" page_num={@online_user_page_num} page_size={@online_user_page_size} total={@online_user_total} />
          </section>
        </section>

        <aside class="monitor-inspector" aria-label="节点与缓存详情">
          <section class="monitor-inspector-section"><header class="monitor-section-heading"><div><span class="monitor-kicker">Runtime</span><h4>节点详情</h4></div><span class="monitor-inspector-icon" aria-hidden="true">⌁</span></header><dl class="monitor-detail-list"><div><dt>节点名称</dt><dd><%= get_in(@monitor_server_info, ["systemInfo", "computerName"]) || "未知" %></dd></div><div><dt>系统版本</dt><dd><%= get_in(@monitor_server_info, ["systemInfo", "osName"]) || "未知" %></dd></div><div><dt>BEAM 运行时</dt><dd><%= get_in(@monitor_server_info, ["jvmInfo", "name"]) || "未知" %></dd></div><div><dt>运行时间</dt><dd><%= get_in(@monitor_server_info, ["jvmInfo", "runTime"]) || "未知" %></dd></div></dl></section>
          <section class="monitor-inspector-section"><header class="monitor-section-heading"><div><span class="monitor-kicker">Cache</span><h4>缓存状态</h4></div><span class="monitor-inspector-icon" aria-hidden="true">◌</span></header><dl class="monitor-detail-list"><div><dt>缓存后端</dt><dd><%= @monitor_cache_info["backend"] || "不可用" %></dd></div><div><dt>缓存条目</dt><dd><%= @monitor_cache_info["cacheEntries"] || 0 %></dd></div><div><dt>验证码条目</dt><dd><%= @monitor_cache_info["captchaEntries"] || 0 %></dd></div></dl></section>
          <section class="monitor-inspector-note"><span class="monitor-kicker">Data status</span><strong><%= monitor_data_status(@monitor_server_info, @monitor_cache_info, @network_status) %></strong><p>数据来自当前节点快照。网络异常或采样缺失时保留最后可见状态。</p></section>
        </aside>
      </div>
    </div>
    """
  end

  defp monitor_metrics(server_info) do
    [
      %{
        label: "CPU 使用率",
        value: monitor_percent(get_in(server_info, ["cpuInfo", "used"])),
        tone: "monitor-chart-bar--primary"
      },
      %{
        label: "主机内存",
        value: monitor_percent(get_in(server_info, ["memoryInfo", "usage"])),
        tone: "monitor-chart-bar--cyan"
      },
      %{
        label: "BEAM 内存",
        value: monitor_percent(get_in(server_info, ["jvmInfo", "usage"])),
        tone: "monitor-chart-bar--violet"
      },
      %{
        label: "磁盘使用率",
        value: monitor_percent(get_in(server_info, ["diskInfos", Access.at(0), "usage"])),
        tone: "monitor-chart-bar--amber"
      }
    ]
  end

  defp monitor_percent(value) when is_integer(value), do: min(max(value, 0), 100)
  defp monitor_percent(value) when is_float(value), do: value |> round() |> monitor_percent()

  defp monitor_percent(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> monitor_percent(number)
      :error -> 0
    end
  end

  defp monitor_percent(_value), do: 0

  defp monitor_metric_y(index), do: 31 + index * 49
  defp monitor_metric_bar_y(index), do: 12 + index * 49
  defp monitor_metric_width(value), do: round(value * 5.14)

  defp monitor_state_class(%{"status" => "ONLINE"}), do: "monitor-live-state--live"
  defp monitor_state_class(%{"status" => "OFFLINE"}), do: "monitor-live-state--offline"
  defp monitor_state_class(%{"status" => "DEGRADED"}), do: "monitor-live-state--partial"
  defp monitor_state_class(_status), do: "monitor-live-state--stale"

  defp monitor_state_label(%{"status" => "ONLINE"}), do: "LIVE · 在线"
  defp monitor_state_label(%{"status" => "OFFLINE"}), do: "OFFLINE · 离线"
  defp monitor_state_label(%{"status" => "DEGRADED"}), do: "PARTIAL · 降级"
  defp monitor_state_label(_status), do: "STALE · 待更新"

  defp monitor_health_title(%{"status" => "ONLINE"}, _server_info), do: "平台运行正常"
  defp monitor_health_title(%{"status" => "DEGRADED"}, _server_info), do: "平台需要关注"
  defp monitor_health_title(%{"status" => "OFFLINE"}, _server_info), do: "网络连接异常"
  defp monitor_health_title(_status, _server_info), do: "等待最新快照"

  defp monitor_health_detail(%{"status" => "ONLINE"}, server_info),
    do: "节点已响应，CPU #{monitor_percent(get_in(server_info, ["cpuInfo", "used"]))}% 使用率。"

  defp monitor_health_detail(%{"status" => "DEGRADED"}, _server_info), do: "当前数据不完整，请检查节点与网络状态。"
  defp monitor_health_detail(%{"status" => "OFFLINE"}, _server_info), do: "保留最近可见数据，恢复连接后可再次刷新。"
  defp monitor_health_detail(_status, _server_info), do: "完成一次刷新后显示当前节点状态。"

  defp monitor_compact_runtime(server_info) do
    case get_in(server_info, ["jvmInfo", "runTime"]) do
      value when is_binary(value) and byte_size(value) > 16 -> String.slice(value, 0, 16) <> "…"
      value when is_binary(value) and value != "" -> value
      _ -> "未知"
    end
  end

  defp monitor_chart_label(server_info) do
    metrics = monitor_metrics(server_info) |> Enum.map_join("、", &"#{&1.label} #{&1.value}%")
    "资源使用快照：#{metrics}。当前值来自节点采样，80% 为建议关注阈值。"
  end

  defp monitor_data_status(server_info, cache_info, network_status) do
    cond do
      network_status["status"] == "OFFLINE" -> "离线快照"
      server_info == %{} or cache_info == %{} -> "部分数据"
      network_status["status"] == "DEGRADED" -> "部分可用"
      true -> "数据正常"
    end
  end
end
