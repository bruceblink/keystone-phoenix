defmodule KeystonePhoenixWeb.Live.AdminPages.Operations do
  @moduledoc "LiveView panels for scheduled jobs, job logs, and runtime monitoring."

  use Phoenix.Component

  import KeystonePhoenixWeb.Live.AdminPages.Pagination
  import KeystonePhoenixWeb.Live.AdminPages.Modal
  import KeystonePhoenixWeb.Live.AdminPages.Navigation, only: [nav_icon: 1]
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminPages.Status
  import KeystonePhoenixWeb.Live.AdminPages.ListToolbar, only: [list_toolbar: 1]

  def jobs(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:active_modal, fn -> nil end)
      |> assign_new(:page_num, fn -> 1 end)
      |> assign_new(:page_size, fn -> 50 end)
      |> assign_new(:job_total, fn -> length(Map.get(assigns, :job_rows, [])) end)
      |> assign_new(:job_filter, fn -> %{"keyword" => ""} end)
      |> assign_new(:selected_job_ids, fn -> [] end)
      |> assign_new(:selected_job_id, fn -> nil end)
      |> assign_new(:selected_job, fn -> nil end)
      |> assign_new(:job_log_rows, fn -> [] end)
      |> assign_new(:job_log_total, fn -> length(Map.get(assigns, :job_log_rows, [])) end)
      |> assign_new(:job_log_page_num, fn -> 1 end)
      |> assign_new(:job_log_page_size, fn -> 50 end)
      |> assign_new(:job_log_feedback, fn -> nil end)

    ~H"""
    <div class="jobs-page operations-page">
      <header class="page-heading">
        <div>
          <p class="eyebrow">OPERATIONS / JOBS</p>
          <h1>定时任务</h1>
          <p class="page-description">查询任务配置、运行状态和执行日志。新增、编辑、启停和手动执行使用独立操作入口。</p>
        </div>
      </header>
      <%= if @job_feedback do %><p id="job-feedback" class={Feedback.class(@job_feedback)} role={Feedback.role(@job_feedback)} aria-live={Feedback.live(@job_feedback)}><%= Feedback.message(@job_feedback) %></p><% end %>
      <section class="card jobs-filter-card">
        <form id="jobs-filter" class="jobs-filter-form filter-form" phx-submit="filter-jobs">
          <label for="jobs-filter-keyword"><span>任务名称、编码或分组</span><input id="jobs-filter-keyword" name="jobKeyword" value={@job_filter["keyword"] || ""} placeholder="按任务名称、调用目标或分组筛选" autocomplete="off" /></label>
          <div class="jobs-filter-actions"><button type="submit" class="button button-primary button-sm"><.nav_icon name="search" />查询</button><button type="button" class="button button-ghost button-sm" phx-click="reset-job-filter">重置</button></div>
        </form>
      </section>
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
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存任务</button><button type="button" class="secondary" phx-click="close-modal" phx-value-modal="job" phx-disable-with="处理中…">取消</button></div>
      </form>
        </.modal>
      <% end %>
      <section class="card jobs-table-card" aria-labelledby="jobs-table-title">
        <.list_toolbar label="定时任务列表操作">
          <button :if={!@read_only} type="button" class="button button-primary button-sm" phx-click="new-job" phx-disable-with="处理中…"><.nav_icon name="plus" />新增任务</button>
          <button :if={!@read_only} type="button" class="button button-danger button-sm" phx-click="delete-jobs" phx-value-job-ids={Enum.join(@selected_job_ids, ",")} phx-confirm="确认删除选中的任务吗？" disabled={@selected_job_ids == []} phx-disable-with="删除中…">删除任务（<%= length(@selected_job_ids) %>）</button>
          <button type="button" class="button button-secondary button-sm" phx-click="refresh-jobs" phx-disable-with="刷新中…"><.nav_icon name="refresh" />刷新任务</button>
        </.list_toolbar>
        <header class="card-header table-card-heading">
          <div><h2 id="jobs-table-title">任务列表</h2><p>共 <%= @job_total %> 个匹配任务</p></div>
          <span class="badge badge-info">系统 API</span>
        </header>
        <%= if @job_rows == [] do %>
          <div class="jobs-empty" role="status"><span class="jobs-empty-icon" aria-hidden="true"><.nav_icon name="clipboard-list" /></span><strong>没有匹配的任务</strong><p>调整筛选条件后重试。</p></div>
        <% else %>
        <div class="jobs-table-wrap" role="region" tabindex="0" aria-label="定时任务列表"><table class="jobs-table"><caption class="sr-only">定时任务列表</caption><thead><tr><th scope="col"><input type="checkbox" aria-label="选择当前任务" checked={Enum.all?(@job_rows, &(to_string(&1["jobId"]) in @selected_job_ids))} phx-click="toggle-all-job-selection" phx-value-selected={if Enum.all?(@job_rows, &(to_string(&1["jobId"]) in @selected_job_ids)), do: "false", else: "true"} /></th><th scope="col">任务</th><th scope="col">分组</th><th scope="col">Cron</th><th scope="col">状态</th><th scope="col">最近运行</th><th scope="col">查看</th><th scope="col">操作</th></tr></thead><tbody>
          <%= for job <- @job_rows do %>
            <% run_at = job["lastRunAt"] || job["lastRunTime"] %>
            <tr class={if to_string(job["jobId"]) == to_string(@selected_job_id), do: "jobs-row-selected", else: nil}><td><input type="checkbox" aria-label={"选择任务 #{job["jobName"]}"} checked={to_string(job["jobId"]) in @selected_job_ids} phx-click="toggle-job-selection" phx-value-job-id={job["jobId"]} phx-value-selected={if to_string(job["jobId"]) in @selected_job_ids, do: "false", else: "true"} /></td><td><div class="job-cell"><span class="job-marker" aria-hidden="true"><.nav_icon name="clipboard-list" /></span><div><strong><%= job["jobName"] %></strong><small><%= job["jobCode"] || job["jobId"] %></small></div></div></td><td><%= job["jobGroup"] || "—" %></td><td><code class="job-cron"><%= job["cronExpression"] || "—" %></code></td><td><span class={"badge #{if job["status"] == 1, do: "badge-success", else: "badge-neutral"}"}><%= if job["status"] == 1, do: "启用", else: "停用" %></span><span :if={job["lastStatus"]} class="job-last-status"><%= job_run_status_label(job["lastStatus"]) %></span></td><td class="jobs-time"><time :if={run_at} id={"job-last-run-at-#{job["jobId"]}"} phx-hook="LocalDateTime" data-utc-time={run_at}><%= run_at %></time><span :if={!run_at}>—</span></td><td><button type="button" class="button button-ghost button-sm" phx-click="select-job" phx-value-job-id={job["jobId"]} phx-disable-with="读取中…">日志</button></td><td :if={!@read_only} class="table-actions"><button type="button" class="button button-ghost button-sm" phx-click="edit-job" phx-value-job-id={job["jobId"]} phx-disable-with="加载中…">编辑</button><button type="button" class="button button-ghost button-sm" phx-click="toggle-job-status" phx-value-job-id={job["jobId"]} phx-value-status={if job["status"] == 1, do: 0, else: 1} phx-disable-with="处理中…"><%= if job["status"] == 1, do: "停用", else: "启用" %></button><button type="button" class="button button-ghost button-sm" phx-click="run-job" phx-value-job-id={job["jobId"]} phx-disable-with="执行中…" disabled={job["status"] != 1}>执行</button></td></tr>
          <% end %>
        </tbody></table></div>
        <% end %>
        <.pagination panel="jobs" page_num={min(@page_num, page_count(@job_total, @page_size))} page_size={@page_size} total={@job_total} />
      </section>
      <section :if={@selected_job_id && @job_log_feedback} class="card job-log-feedback-card" aria-labelledby="job-log-feedback-title">
        <div>
          <h2 id="job-log-feedback-title">任务详情读取反馈</h2>
          <p id="job-log-feedback" class={Feedback.class(@job_log_feedback)} role={Feedback.role(@job_log_feedback)} aria-live={Feedback.live(@job_log_feedback)}><%= Feedback.message(@job_log_feedback) %></p>
        </div>
        <button type="button" class="button button-secondary button-sm" phx-click="select-job" phx-value-job-id={@selected_job_id} phx-disable-with="读取中…">重试读取任务详情</button>
      </section>
      <%= if @selected_job_id do %>
        <% selected_job = @selected_job || Enum.find(@job_rows, &(to_string(&1["jobId"]) == to_string(@selected_job_id))) %>
        <% selected_logs = @job_log_rows %>
        <section :if={selected_job} class="card job-logs-card" aria-labelledby="selected-job-logs-title">
          <.list_toolbar label="任务执行日志操作">
            <button type="button" class="button button-ghost button-sm" phx-click="refresh-job-logs" phx-disable-with="刷新中…"><.nav_icon name="refresh" />刷新</button>
          </.list_toolbar>
          <header class="card-header">
            <div><h2 id="selected-job-logs-title"><%= selected_job["jobName"] %> · 执行日志</h2><p>共 <%= @job_log_total %> 条记录</p></div>
            <span class="badge badge-info">只读</span>
          </header>
          <%= if @job_log_feedback && selected_logs == [] do %>
            <div class="jobs-empty" role="status"><strong>当前无法读取执行日志</strong><p>请使用上方重试入口重新读取任务详情。</p></div>
          <% else %>
          <%= if selected_logs == [] do %>
            <div class="jobs-empty" role="status"><span class="jobs-empty-icon" aria-hidden="true"><.nav_icon name="clipboard-list" /></span><strong>暂无执行日志</strong><p>任务运行后，日志会显示在这里。</p></div>
          <% else %>
            <div class="jobs-table-wrap"><table class="jobs-table"><caption class="sr-only">执行日志</caption><thead><tr><th scope="col">时间</th><th scope="col">触发方式</th><th scope="col">状态</th><th scope="col">耗时</th><th scope="col">说明</th></tr></thead><tbody>
              <%= for log <- selected_logs do %>
                <tr><td class="jobs-time"><%= job_log_time(log) %></td><td><%= job_log_trigger(log) %></td><td><span class={"badge #{job_log_badge(log["status"])}"}><%= job_log_status(log["status"]) %></span></td><td><%= job_log_duration(log) %></td><td class="audit-detail"><%= log["jobMessage"] || log["exceptionInfo"] || "—" %></td></tr>
              <% end %>
            </tbody></table></div>
          <% end %>
          <% end %>
          <.pagination panel="job-logs" page_num={min(@job_log_page_num, page_count(@job_log_total, @job_log_page_size))} page_size={@job_log_page_size} total={@job_log_total} />
        </section>
      <% end %>
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
    <div class="job-logs-page operations-page">
      <header class="page-heading">
        <div>
          <p class="eyebrow">OPERATIONS / JOB LOGS</p>
          <h1>任务日志</h1>
          <p class="page-description">查看调度任务的执行结果、消息和时间信息。日志页面保持只读。</p>
        </div>
      </header>
      <%= if @job_log_feedback do %><p id="job-log-feedback" class={Feedback.class(@job_log_feedback)} role={Feedback.role(@job_log_feedback)} aria-live={Feedback.live(@job_log_feedback)}><%= Feedback.message(@job_log_feedback) %></p><% end %>
      <section class="card job-logs-card table-card" aria-labelledby="job-logs-title">
        <.list_toolbar label="任务日志列表操作">
          <button type="button" class="refresh secondary" phx-click="refresh-job-logs" phx-disable-with="刷新中…"><.nav_icon name="refresh" />刷新任务日志</button>
        </.list_toolbar>
        <header class="card-header table-card-heading">
          <div><h2 id="job-logs-title">执行日志</h2><p>共 <%= length(@job_log_rows) %> 条记录</p></div>
          <span class="status-badge status-badge--normal">只读</span>
        </header>
        <%= if @job_log_rows == [] do %>
          <p class="jobs-empty table-empty" role="status"><span class="jobs-empty-icon" aria-hidden="true"><.nav_icon name="clipboard-list" /></span><strong>暂无任务日志</strong><span>任务运行后，日志会显示在这里。</span></p>
        <% else %>
          <div class="table-scroll" role="region" tabindex="0" aria-label="任务日志列表"><table class="jobs-table"><caption class="sr-only">任务日志列表</caption><thead><tr><th scope="col">任务</th><th scope="col">分组</th><th scope="col">调用目标</th><th scope="col">状态</th><th scope="col">消息</th><th scope="col">开始时间</th><th scope="col">结束时间</th></tr></thead><tbody>
            <%= for log <- page_rows(@job_log_rows, @page_num, @page_size) do %>
              <tr><td><strong><%= log["jobName"] %></strong></td><td><%= log["jobGroup"] %></td><td><code><%= log["invokeTarget"] %></code></td><td><span class={"status-badge #{Status.job_log(log["status"])}"}><%= log["statusStr"] || if(log["status"] == 1, do: "成功", else: "失败") %></span></td><td><%= log["jobMessage"] || log["exceptionInfo"] || "" %></td><td><%= log["startTime"] || "" %></td><td><%= log["endTime"] || "" %></td></tr>
            <% end %>
          </tbody></table></div>
          <.pagination panel="job-logs" page_num={min(@page_num, page_count(length(@job_log_rows), @page_size))} page_size={@page_size} total={length(@job_log_rows)} />
        <% end %>
      </section>
    </div>
    """
  end

  # 将旧任务日志字段转换为 admin-web 同一组可读列。
  defp job_run_status_label("SUCCESS"), do: "最近成功"
  defp job_run_status_label("FAILED"), do: "最近失败"
  defp job_run_status_label("SKIPPED"), do: "最近跳过"
  defp job_run_status_label(status), do: status

  defp job_log_time(log), do: log["createdAt"] || log["startTime"] || log["finishedAt"] || "—"
  defp job_log_trigger(%{"triggerType" => 1}), do: "自动调度"
  defp job_log_trigger(_log), do: "手动触发"
  defp job_log_status(1), do: "成功"
  defp job_log_status(2), do: "跳过"
  defp job_log_status(0), do: "失败"
  defp job_log_status("1"), do: "成功"
  defp job_log_status("2"), do: "跳过"
  defp job_log_status(_status), do: "未知"
  defp job_log_badge(status) when status in [1, "1"], do: "badge-success"
  defp job_log_badge(status) when status in [2, "2"], do: "badge-warning"
  defp job_log_badge(_status), do: "badge-danger"

  defp job_log_duration(%{"durationMs" => duration}) when is_integer(duration),
    do: "#{duration} ms"

  defp job_log_duration(%{"duration" => duration}) when is_integer(duration), do: "#{duration} ms"
  defp job_log_duration(_log), do: "—"

  def monitor(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:online_user_page_num, fn -> 1 end)
      |> assign_new(:online_user_page_size, fn -> 50 end)
      |> assign_new(:online_user_total, fn -> length(assigns[:online_user_rows] || []) end)
      |> assign_new(:security_access, fn -> false end)
      |> assign_new(:monitor_feedback, fn -> nil end)
      |> assign_new(:monitor_loading, fn -> false end)
      |> assign_new(:monitor_initial_error, fn -> nil end)
      |> assign_new(:monitor_help_open, fn -> false end)
      |> assign_new(:monitor_trend, fn ->
        monitor_trend(assigns[:monitor_server_info] || %{}, assigns[:network_status] || %{})
      end)

    ~H"""
    <div class="monitor-page">
      <div class="page-heading">
        <div>
          <p class="eyebrow">OPERATIONS / MONITORING</p>
          <h1>运行监控</h1>
          <p class="page-description">快速判断平台健康，定位异常，并处理在线会话。</p>
        </div>
        <div class="heading-actions">
          <button type="button" class="button button-secondary button-sm refresh" phx-click="refresh-monitor" phx-disable-with="刷新中…">刷新快照</button>
          <button type="button" class="button button-ghost button-sm" aria-label="监控帮助" aria-expanded={@monitor_help_open} phx-click="toggle-monitor-help">?</button>
        </div>
      </div>

      <div :if={@monitor_help_open} class="monitor-help-panel" role="note">
        <span aria-hidden="true">?</span>
        <div><strong>如何阅读监控</strong><p>状态和趋势来自系统 API。显示“—”表示当前后端没有提供该指标；PARTIAL 表示部分节点数据可用。</p></div>
        <button type="button" class="button button-ghost button-sm" aria-label="关闭监控帮助" phx-click="toggle-monitor-help">关闭</button>
      </div>

      <div class="monitor-status-bar">
        <div class="status-leading">
          <span class={"status-pulse #{monitor_badge_tone(@network_status)}"} aria-hidden="true"></span>
          <span class={"badge badge-#{monitor_badge_tone(@network_status)}"} role="status"><%= monitor_state_short_label(@network_status) %></span>
          <span><%= monitor_state_detail(@network_status) %></span>
        </div>
        <div class="status-meta">
          <span><%= @network_status["checkedAt"] || "等待快照" %></span>
          <span class="status-source">来源：系统 API</span>
        </div>
      </div>

      <%= if @monitor_feedback do %>
        <p id="monitor-feedback" class={Feedback.class(@monitor_feedback)} role={Feedback.role(@monitor_feedback)} aria-live={Feedback.live(@monitor_feedback)}><%= Feedback.message(@monitor_feedback) %></p>
      <% end %>

      <div :if={@monitor_loading} id="monitor-loading" class="card monitor-query-state" role="status" aria-live="polite">
        <strong>正在读取监控快照</strong><span>系统 API 返回后会显示最新指标。</span>
      </div>

      <div :if={@monitor_initial_error} id="monitor-initial-error" class="card monitor-query-state monitor-query-error" role="alert">
        <strong>监控数据加载失败</strong>
        <span><%= Feedback.message(@monitor_initial_error) %></span>
        <button type="button" class="button button-primary button-sm" phx-click="retry-monitor" phx-disable-with="重试中…">重试</button>
      </div>

      <div :if={!@monitor_loading && is_nil(@monitor_initial_error)} class="monitor-grid">
        <section class="monitor-main">
          <section class="card trend-card">
            <header class="card-header">
              <div><h2>主机资源趋势</h2><p>最近 30 分钟 · 采样百分比</p></div>
              <span class="node-chip"><span aria-hidden="true">●</span><%= monitor_node_name(@monitor_server_info) %></span>
            </header>
            <%= if monitor_trend_empty?(@monitor_trend) do %>
              <div class="trend-chart trend-chart-empty" role="status" aria-live="polite"><strong>暂无采样数据</strong><span>系统 API 尚未返回 CPU 或内存趋势。</span></div>
            <% else %>
              <div class="trend-chart" role="img" aria-label={monitor_chart_label(@monitor_trend)}>
                <svg viewBox="0 0 720 232" preserveAspectRatio="none" aria-hidden="true">
                  <g class="trend-chart-grid">
                    <line x1="42" y1="18" x2="704" y2="18" /><line x1="42" y1="67" x2="704" y2="67" /><line x1="42" y1="116" x2="704" y2="116" /><line x1="42" y1="165" x2="704" y2="165" /><line x1="42" y1="214" x2="704" y2="214" />
                    <line class="trend-chart-threshold" x1="42" y1="55.2" x2="704" y2="55.2" />
                  </g>
                  <g class="trend-chart-axis"><text x="4" y="22">100%</text><text x="13" y="71">75%</text><text x="13" y="120">50%</text><text x="13" y="169">25%</text><text x="22" y="218">0%</text></g>
                  <text class="trend-chart-threshold-label" x="548" y="49">80% 关注阈值</text>
                  <polyline class="trend-chart-line trend-chart-line-cyan" points={monitor_trend_points(@monitor_trend, :cpu)} />
                  <polyline class="trend-chart-line trend-chart-line-indigo" points={monitor_trend_points(@monitor_trend, :memory)} />
                  <%= for {point, index} <- Enum.with_index(@monitor_trend) do %>
                    <%= if is_number(point.cpu) do %><circle class="trend-chart-point trend-chart-point-cyan" cx={monitor_trend_x(index, length(@monitor_trend))} cy={monitor_trend_y(point.cpu)} r="2.5" /><% end %>
                    <%= if is_number(point.memory) do %><circle class="trend-chart-point trend-chart-point-indigo" cx={monitor_trend_x(index, length(@monitor_trend))} cy={monitor_trend_y(point.memory)} r="2.5" /><% end %>
                  <% end %>
                  <text class="trend-chart-time" x="42" y="230"><%= monitor_trend_time(List.first(@monitor_trend)) %></text>
                  <text class="trend-chart-time" x="704" y="230" text-anchor="end"><%= monitor_trend_time(List.last(@monitor_trend)) %></text>
                </svg>
              </div>
            <% end %>
            <div class="trend-summary">
              <div><span class="line-key line-key-cyan"></span>CPU <strong><%= monitor_value_label(monitor_percent(get_in(@monitor_server_info, ["cpuInfo", "used"]))) %></strong></div>
              <div><span class="line-key line-key-indigo"></span>内存 <strong><%= monitor_value_label(monitor_percent(get_in(@monitor_server_info, ["memoryInfo", "usage"]))) %></strong></div>
              <span class="threshold-note">关注阈值 80% · 来源：系统 API</span>
            </div>
          </section>

          <div class="metric-grid">
            <article class="card metric-card metric-card-cyan">
              <div class="metric-head"><span class="metric-icon" aria-hidden="true"><.nav_icon name="activity" /></span><span>CPU 使用率</span></div>
              <strong class="metric-value"><%= monitor_value_label(monitor_percent(get_in(@monitor_server_info, ["cpuInfo", "used"]))) %></strong>
              <div class="metric-detail"><span>系统负载</span><span class="metric-progress-label"><%= monitor_value_label(monitor_percent(get_in(@monitor_server_info, ["cpuInfo", "used"]))) %></span></div>
              <div class="progress-track"><span style={"width: #{monitor_value_width(get_in(@monitor_server_info, ["cpuInfo", "used"]))}%"}></span></div>
            </article>
            <article class="card metric-card metric-card-indigo">
              <div class="metric-head"><span class="metric-icon" aria-hidden="true">▦</span><span>主机内存</span></div>
              <strong class="metric-value"><%= monitor_value_label(monitor_percent(get_in(@monitor_server_info, ["memoryInfo", "usage"]))) %></strong>
              <div class="metric-detail"><span>Java 堆已使用</span><span class="metric-progress-label"><%= monitor_value_label(monitor_percent(get_in(@monitor_server_info, ["memoryInfo", "usage"]))) %></span></div>
              <div class="progress-track"><span style={"width: #{monitor_value_width(get_in(@monitor_server_info, ["memoryInfo", "usage"]))}%"}></span></div>
            </article>
            <article class="card metric-card metric-card-amber">
              <div class="metric-head"><span class="metric-icon" aria-hidden="true"><.nav_icon name="hard-drive" /></span><span>磁盘空间</span></div>
              <strong class="metric-value"><%= monitor_value_label(monitor_percent(get_in(@monitor_server_info, ["diskInfos", Access.at(0), "usage"]))) %></strong>
              <div class="metric-detail"><span>系统 API 当前值</span><span class="metric-progress-label"><%= monitor_value_label(monitor_percent(get_in(@monitor_server_info, ["diskInfos", Access.at(0), "usage"]))) %></span></div>
              <div class="progress-track"><span style={"width: #{monitor_value_width(get_in(@monitor_server_info, ["diskInfos", Access.at(0), "usage"]))}%"}></span></div>
            </article>
          </div>

          <section class="card sessions-card">
            <header class="card-header">
              <div><h2>在线会话</h2><p><%= @online_user_total %> 个活跃会话 · 仅展示当前节点</p></div>
              <span class="badge badge-success"><span class="tiny-dot"></span>在线</span>
            </header>
            <div :if={@online_user_rows == []} class="table-empty sessions-empty" role="status"><strong>暂无在线会话</strong><span>当前节点没有活跃会话。</span></div>
            <div :if={@online_user_rows != []} class="session-list table-scroll">
              <table class="monitor-session-table"><caption class="sr-only">在线会话列表</caption><thead><tr><th scope="col">用户</th><th scope="col">部门</th><th scope="col">来源地址</th><th scope="col">登录时间</th><th scope="col">操作</th></tr></thead><tbody>
                <%= for user <- @online_user_rows do %>
                  <tr><td><strong><%= user["username"] %></strong></td><td><%= user["deptName"] || "未分配部门" %></td><td><code><%= user["ipAddress"] %></code></td><td><%= user["loginTime"] %></td><td :if={!@read_only}><button type="button" class="button button-danger button-sm" phx-confirm="确认下线此会话吗？" phx-click="logout-online-user" phx-value-token-id={user["tokenId"]} phx-disable-with="下线中…">强制下线</button></td></tr>
                <% end %>
              </tbody></table>
            </div>
            <.pagination panel="online-users" page_num={@online_user_page_num} page_size={@online_user_page_size} total={@online_user_total} />
          </section>
        </section>

        <aside class="monitor-inspector">
          <section class="card">
            <header class="card-header"><div><h2>节点详情</h2><p>当前健康快照</p></div></header>
            <div class="inspector-list">
              <div class="info-row"><span class="info-icon" aria-hidden="true">◆</span><div><span>节点</span><strong><%= monitor_node_name(@monitor_server_info) %></strong></div></div>
              <div class="info-row"><span class="info-icon" aria-hidden="true">↕</span><div><span>网络入口</span><strong>—</strong><small>系统 API 未提供流量采样</small></div></div>
              <div class="info-row"><span class="info-icon" aria-hidden="true"><.nav_icon name="activity" /></span><div><span>处理器</span><strong><%= get_in(@monitor_server_info, ["cpuInfo", "cpuNum"]) || "—" %></strong><small>逻辑处理器数量</small></div></div>
              <div class="info-row"><span class="info-icon" aria-hidden="true">◇</span><div><span>活动会话</span><strong><%= @online_user_total %></strong><small>系统 API 当前活动会话</small></div></div>
            </div>
          </section>
          <section class="card beam-card">
            <header class="card-header"><div><h2>运行时指标</h2><p>系统 API 当前可用指标</p></div></header>
            <div class="beam-stat"><span>BEAM 内存使用率</span><strong><%= monitor_value_label(monitor_percent(get_in(@monitor_server_info, ["jvmInfo", "usage"]))) %></strong></div>
            <div class="beam-stat"><span>Reductions</span><strong>—</strong></div>
            <div class="beam-stat"><span>网络流量</span><strong>—</strong></div>
          </section>
        </aside>
      </div>
    </div>
    """
  end

  # 现有 Phoenix API 只返回当前快照。保留一个真实采样点，未来可直接替换为历史列表。
  defp monitor_trend(server_info, network_status) do
    cpu = monitor_percent(get_in(server_info, ["cpuInfo", "used"]))
    memory = monitor_percent(get_in(server_info, ["memoryInfo", "usage"]))

    if is_nil(cpu) and is_nil(memory) do
      []
    else
      [%{timestamp: network_status["checkedAt"], cpu: cpu, memory: memory}]
    end
  end

  # 将后端快照转换为 admin-web 使用的状态标签，缺失值保持中性显示。
  defp monitor_badge_tone(%{"status" => "ONLINE"}), do: "success"
  defp monitor_badge_tone(%{"status" => "DEGRADED"}), do: "warning"
  defp monitor_badge_tone(%{"status" => "OFFLINE"}), do: "danger"
  defp monitor_badge_tone(_status), do: "neutral"

  defp monitor_state_short_label(%{"status" => "ONLINE"}), do: "LIVE"
  defp monitor_state_short_label(%{"status" => "DEGRADED"}), do: "PARTIAL"
  defp monitor_state_short_label(%{"status" => "OFFLINE"}), do: "OFFLINE"
  defp monitor_state_short_label(_status), do: "STALE"

  defp monitor_state_detail(%{"status" => "ONLINE"}), do: "系统 API 正常响应"
  defp monitor_state_detail(%{"status" => "DEGRADED"}), do: "部分指标暂不可用"
  defp monitor_state_detail(%{"status" => "OFFLINE"}), do: "无法读取最新快照"
  defp monitor_state_detail(_status), do: "等待系统 API 快照"

  defp monitor_node_name(server_info) do
    get_in(server_info, ["systemInfo", "computerName"]) ||
      get_in(server_info, ["systemInfo", "hostName"]) || "当前节点"
  end

  defp monitor_value_width(value) do
    case monitor_percent(value) do
      number when is_number(number) -> number
      _ -> 0
    end
  end

  defp monitor_percent(value) when is_integer(value), do: min(max(value, 0), 100)
  defp monitor_percent(value) when is_float(value), do: value |> round() |> monitor_percent()

  defp monitor_percent(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> monitor_percent(number)
      :error -> nil
    end
  end

  defp monitor_percent(_value), do: nil

  defp monitor_value_label(value) when is_number(value), do: "#{value}%"
  defp monitor_value_label(_value), do: "—"

  defp monitor_trend_empty?(trend), do: Enum.all?(trend, &(is_nil(&1.cpu) and is_nil(&1.memory)))

  defp monitor_trend_x(_index, count) when count <= 1, do: 373
  defp monitor_trend_x(index, count), do: 42 + round(index * 662 / (count - 1))

  defp monitor_trend_y(value) when is_number(value), do: 214 - value * 1.96

  defp monitor_trend_points(trend, key) do
    trend
    |> Enum.with_index()
    |> Enum.flat_map(fn {point, index} ->
      value = Map.get(point, key)

      if is_number(value),
        do: ["#{monitor_trend_x(index, length(trend))},#{monitor_trend_y(value)}"],
        else: []
    end)
    |> Enum.join(" ")
  end

  defp monitor_trend_time(%{timestamp: timestamp}) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} -> Calendar.strftime(datetime, "%H:%M")
      _ -> "当前"
    end
  end

  defp monitor_trend_time(_point), do: "当前"

  defp monitor_chart_label(trend) do
    "CPU 和内存 30 分钟趋势图，共 #{length(trend)} 个采样点；80% 为建议关注阈值。"
  end
end
