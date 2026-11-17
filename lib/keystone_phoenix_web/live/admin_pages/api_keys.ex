defmodule KeystonePhoenixWeb.Live.AdminPages.ApiKeys do
  @moduledoc "LiveView panel for API Key metadata and lifecycle operations."

  use Phoenix.Component

  import KeystonePhoenixWeb.Live.AdminPages.Modal
  import KeystonePhoenixWeb.Live.AdminPages.Pagination, only: [pagination: 1]
  import KeystonePhoenixWeb.Live.AdminPages.Navigation, only: [nav_icon: 1]
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenix.Authz.PermissionCatalog
  import KeystonePhoenixWeb.Live.AdminPages.ListToolbar, only: [list_toolbar: 1]

  def api_keys(assigns) do
    assigns =
      assigns
      |> assign_new(:api_key_rows, fn -> [] end)
      |> assign_new(:api_key_total, fn -> nil end)
      |> assign_new(:api_key_page_num, fn -> 1 end)
      |> assign_new(:api_key_page_size, fn -> 20 end)
      |> assign_new(:api_key_feedback, fn -> nil end)
      |> assign_new(:api_key_form, fn -> empty_form() end)
      |> assign_new(:api_key_query, fn -> "" end)
      |> assign_new(:api_key_status, fn -> "all" end)
      |> assign_new(:api_key_scope_query, fn -> "" end)
      |> assign_new(:scope_entries, fn -> scope_entries(assigns[:permissions]) end)
      |> assign_new(:issued_api_key, fn -> nil end)
      |> assign_new(:permissions, fn -> [] end)
      |> assign_new(:read_only, fn -> false end)

    ~H"""
    <div class="panel api-keys-page">
      <div class="page-heading">
        <div>
          <p class="eyebrow">SECURITY / API KEYS</p>
          <h1>API Key 管理</h1>
          <p class="page-description">查询当前账号的机器凭据、授权范围和生命周期状态。密钥明文只在签发时返回一次。</p>
        </div>
      </div>
      <%= if @api_key_feedback do %>
        <p id="api-key-feedback" class={Feedback.class(@api_key_feedback)} role={Feedback.role(@api_key_feedback)} aria-live={Feedback.live(@api_key_feedback)}><%= Feedback.message(@api_key_feedback) %></p>
      <% end %>
      <%= if @issued_api_key do %>
        <div id="api-key-secret" class="card secret-banner" role="alert">
          <div>
            <strong>请立即保存这枚 API Key</strong>
            <p>明文只在当前页面内存中展示一次。关闭提示后不会再次读取。</p>
            <code><%= @issued_api_key.api_key %></code>
          </div>
          <button type="button" class="button button-ghost secondary" phx-click="dismiss-api-key-secret">关闭</button>
        </div>
      <% end %>
      <%= if @active_modal == "api-key" do %>
        <.modal id="api-key-modal" title="签发 API Key" description="API Key 只返回一次明文。请在签发成功后立即保存。">
          <form id="api-key-form" phx-change="filter-api-key-scopes" phx-submit="save-api-key" phx-hook="LocalDateTimeInput" aria-describedby="api-key-feedback">
            <div class="form-grid">
              <div><label for="api-key-name">密钥名称</label><input id="api-key-name" name="name" value={@api_key_form["name"]} required /></div>
              <div><label for="api-key-expires-local">到期时间</label><input id="api-key-expires-local" type="datetime-local" name="expiresAtLocal" value={@api_key_form["expiresAtLocal"]} /></div>
              <input id="api-key-expires-utc" type="hidden" name="expiresAt" value={@api_key_form["expiresAt"]} />
              <input type="hidden" name="scopes" value={@api_key_form["scopes"]} />
            </div>
            <fieldset class="api-key-scope-picker"><legend>授权范围 *</legend><div class="api-key-scope-toolbar"><label for="api-key-scope-query">搜索接口权限</label><input id="api-key-scope-query" name="scopeQuery" value={@api_key_scope_query} placeholder="例如 user:read" phx-debounce="200" autocomplete="off" /><span><%= selected_scope_count(@api_key_form["scopes"]) %> 项已选择</span></div><div class="api-key-scope-groups"><%= for {resource, entries} <- grouped_scope_entries(@scope_entries, @api_key_scope_query) do %><section class="api-key-scope-group"><h4><%= scope_resource_label(resource) %></h4><div><%= for entry <- entries do %><label class="checkbox-label"><input type="checkbox" phx-click="toggle-api-key-scope" phx-value-scope={entry["permission"]} phx-value-selected={if scope_selected?(@api_key_form["scopes"], entry["permission"]), do: "false", else: "true"} checked={scope_selected?(@api_key_form["scopes"], entry["permission"])} /><span><%= scope_action_label(entry["action"]) %></span><code><%= entry["permission"] %></code></label><% end %></div></section><% end %></div><p :if={@scope_entries == []} class="form-help" role="status">没有可配置的接口权限。</p><p class="form-help">权限目录来自当前系统；签发时还会检查签发账号当前权限。</p></fieldset>
            <div class="form-actions"><button type="submit" class="button button-primary" phx-disable-with="签发中…">签发密钥</button><button type="button" class="button button-ghost secondary" phx-click="close-modal">取消</button></div>
          </form>
        </.modal>
      <% end %>
      <section class="card filter-card api-keys-filter-card" aria-labelledby="api-keys-filter-title">
        <div class="card-header">
          <div>
            <h2 id="api-keys-filter-title">筛选 API Key</h2>
            <p>按名称、前缀、授权范围或生命周期状态筛选。</p>
          </div>
        </div>
        <form class="filter-form api-keys-filter-form" phx-submit="filter-api-keys">
          <label for="api-key-query"><span>名称、前缀或范围</span><input id="api-key-query" name="query" value={@api_key_query} placeholder="按名称、前缀或权限范围筛选" autocomplete="off" /></label>
          <label for="api-key-status"><span>状态</span><select id="api-key-status" name="status"><option value="all" selected={@api_key_status == "all"}>全部状态</option><option value="active" selected={@api_key_status == "active"}>有效</option><option value="revoked" selected={@api_key_status == "revoked"}>已撤销</option></select></label>
          <div class="filter-actions api-keys-filter-actions"><button type="submit" class="button button-primary refresh"><.nav_icon name="search" />查询</button><button type="button" class="button button-ghost refresh secondary" phx-click="filter-api-keys" phx-value-query="" phx-value-status="all">重置</button></div>
        </form>
      </section>
      <section class="card table-card api-keys-table-card" aria-labelledby="api-keys-table-title">
        <.list_toolbar label="API Key 列表操作">
          <button :if={"api-key:create" in @permissions} type="button" class="button button-primary refresh" phx-click="new-api-key" phx-disable-with="处理中…"><.nav_icon name="plus" />签发 API Key</button>
          <button type="button" class="button button-secondary refresh secondary" phx-click="refresh-api-keys" phx-disable-with="刷新中…"><.nav_icon name="refresh" />刷新列表</button>
        </.list_toolbar>
        <header class="card-header table-card-heading">
          <div><h2 id="api-keys-table-title">API Key 列表</h2><p>共 <%= @api_key_total || length(@api_key_rows) %> 个匹配凭据</p></div>
          <span class="badge badge-info">仅显示元数据</span>
        </header>
        <%= if @api_key_rows == [] do %>
          <div class="api-keys-empty empty-state" role="status"><strong>暂无匹配的 API Key</strong><p>调整筛选条件后重试，或清空筛选条件查看全部凭据。</p></div>
        <% else %>
          <div class="table-wrap"><div class="table-scroll" role="region" tabindex="0" aria-label="API Key 列表">
            <table class="api-keys-table"><caption class="sr-only">API Key 列表</caption><thead><tr><th scope="col">名称</th><th scope="col">密钥前缀</th><th scope="col">授权范围</th><th scope="col">创建时间</th><th scope="col">最近使用</th><th scope="col">到期时间</th><th scope="col">状态</th><th scope="col">操作</th></tr></thead><tbody>
              <%= for key <- @api_key_rows do %>
                <% revoked = not is_nil(key.revoked_at) %>
                <tr>
                  <td><div class="api-key-cell"><strong><%= key.name %></strong><small><%= key.id %></small></div></td>
                  <td><code>ks_live_<%= key.prefix %>_••••</code></td>
                  <td><div class="api-key-scopes"><%= for scope <- key.scopes do %><span class="badge badge-neutral"><%= scope %></span><% end %></div></td>
                  <td>
                    <time :if={key.created_at} id={"api-key-created-at-#{key.id}"} phx-hook="LocalDateTime" data-utc-time={format_datetime(key.created_at)}><%= format_datetime(key.created_at) %></time>
                    <span :if={!key.created_at}>—</span>
                  </td>
                  <td>
                    <time :if={key.last_used_at} id={"api-key-last-used-at-#{key.id}"} phx-hook="LocalDateTime" data-utc-time={format_datetime(key.last_used_at)}><%= format_datetime(key.last_used_at) %></time>
                    <span :if={!key.last_used_at}>从未使用</span>
                  </td>
                  <td>
                    <time :if={key.expires_at} id={"api-key-expires-at-#{key.id}"} phx-hook="LocalDateTime" data-utc-time={format_datetime(key.expires_at)}><%= format_datetime(key.expires_at) %></time>
                    <span :if={!key.expires_at}>永不过期</span>
                  </td>
                  <td><span class={if revoked, do: "status-badge status-badge--failure", else: "status-badge status-badge--success"}><%= if revoked, do: "已撤销", else: "有效" %></span></td>
                  <td class="table-actions">
                    <button :if={!revoked and "api-key:rotate" in @permissions} type="button" class="button button-ghost refresh" phx-click="rotate-api-key" phx-value-id={key.id} phx-disable-with="轮换中…">轮换</button>
                    <button :if={!revoked and "api-key:revoke" in @permissions} type="button" class="button button-danger refresh danger-action" phx-confirm="确认撤销此 API Key 吗？" phx-click="revoke-api-key" phx-value-id={key.id} phx-disable-with="撤销中…">撤销</button>
                  </td>
                </tr>
              <% end %>
            </tbody></table>
          </div></div>
        <% end %>
        <div class="table-card-footer">
          <.pagination panel="api-keys" page_num={@api_key_page_num} page_size={@api_key_page_size} total={@api_key_total || length(@api_key_rows)} />
        </div>
      </section>
    </div>
    """
  end

  def empty_form,
    do: %{"name" => "", "scopes" => "", "expiresAt" => "", "expiresAtLocal" => ""}

  def scope_entries(permissions) do
    allowed = MapSet.new(List.wrap(permissions))

    PermissionCatalog.entries()
    |> Enum.map(fn entry ->
      %{
        "permission" => entry.permission,
        "resource" => entry.resource,
        "action" => entry.action,
        "description" => entry.description,
        "risk" => to_string(entry.risk),
        "registered" => entry.registered?,
        "allowed" => MapSet.member?(allowed, entry.permission)
      }
    end)
    |> Enum.filter(&(&1["registered"] and &1["allowed"]))
  end

  def grouped_scope_entries(entries, query) do
    normalized = String.downcase(String.trim(to_string(query)))

    entries
    |> Enum.filter(fn entry ->
      normalized == "" or
        String.contains?(
          String.downcase("#{entry["permission"]} #{entry["description"]} #{entry["action"]}"),
          normalized
        )
    end)
    |> Enum.group_by(& &1["resource"])
    |> Enum.sort_by(&elem(&1, 0))
  end

  def selected_scope_count(scopes), do: length(parse_scopes(scopes))

  def scope_selected?(scopes, permission), do: permission in parse_scopes(scopes)

  def scope_resource_label("api-key"), do: "API Key"
  def scope_resource_label("user"), do: "用户管理"
  def scope_resource_label("role"), do: "角色管理"
  def scope_resource_label("menu"), do: "菜单与权限"
  def scope_resource_label("job"), do: "定时任务"
  def scope_resource_label("notice"), do: "通知公告"
  def scope_resource_label("audit"), do: "操作审计"
  def scope_resource_label("login-log"), do: "登录日志"
  def scope_resource_label("operation-log"), do: "操作日志"
  def scope_resource_label(resource), do: resource

  def scope_action_label("create"), do: "新增"
  def scope_action_label("delete"), do: "删除"
  def scope_action_label("read"), do: "读取"
  def scope_action_label("update"), do: "修改"
  def scope_action_label("export"), do: "导出"
  def scope_action_label("import"), do: "导入"
  def scope_action_label("manage"), do: "管理"
  def scope_action_label("refresh"), do: "刷新"
  def scope_action_label("revoke"), do: "撤销"
  def scope_action_label("rotate"), do: "轮换"
  def scope_action_label("run"), do: "执行"
  def scope_action_label("assign"), do: "分配"
  def scope_action_label("reset-password"), do: "重置密码"
  def scope_action_label("update-status"), do: "修改状态"
  def scope_action_label(action), do: action

  defp parse_scopes(scopes) do
    scopes
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp format_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_datetime(value), do: to_string(value)
end
