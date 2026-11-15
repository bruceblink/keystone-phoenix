defmodule KeystonePhoenixWeb.Live.AdminPages.ApiKeys do
  @moduledoc "LiveView panel for API Key metadata and lifecycle operations."

  use Phoenix.Component

  import KeystonePhoenixWeb.Live.AdminPages.Modal
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback

  def api_keys(assigns) do
    assigns =
      assigns
      |> assign_new(:api_key_rows, fn -> [] end)
      |> assign_new(:api_key_feedback, fn -> nil end)
      |> assign_new(:api_key_form, fn -> empty_form() end)
      |> assign_new(:api_key_query, fn -> "" end)
      |> assign_new(:api_key_status, fn -> "all" end)
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
        <div class="heading-actions form-actions">
          <button :if={"api-key:create" in @permissions} type="button" class="button button-primary refresh" phx-click="new-api-key" phx-disable-with="处理中…">签发 API Key</button>
          <button type="button" class="button button-secondary refresh secondary" phx-click="refresh-api-keys" phx-disable-with="刷新中…">刷新列表</button>
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
          <form phx-submit="save-api-key" aria-describedby="api-key-feedback">
            <div class="form-grid">
              <div><label for="api-key-name">密钥名称</label><input id="api-key-name" name="name" value={@api_key_form["name"]} required /></div>
              <div><label for="api-key-expires">到期时间</label><input id="api-key-expires" type="datetime-local" name="expiresAt" value={@api_key_form["expiresAt"]} /></div>
              <div class="wide"><label for="api-key-scopes">授权范围</label><input id="api-key-scopes" name="scopes" value={@api_key_form["scopes"]} placeholder="user:read,role:read" required /></div>
            </div>
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
          <div class="filter-actions api-keys-filter-actions"><button type="submit" class="button button-primary refresh">查询</button><button type="button" class="button button-ghost refresh secondary" phx-click="filter-api-keys" phx-value-query="" phx-value-status="all">重置</button></div>
        </form>
      </section>
      <section class="card table-card api-keys-table-card" aria-labelledby="api-keys-table-title">
        <header class="card-header table-card-heading">
          <div><h2 id="api-keys-table-title">API Key 列表</h2><p>共 <%= length(filtered_rows(@api_key_rows, @api_key_query, @api_key_status)) %> 个匹配凭据</p></div>
          <span class="badge badge-info">仅显示元数据</span>
        </header>
        <%= if filtered_rows(@api_key_rows, @api_key_query, @api_key_status) == [] do %>
          <div class="api-keys-empty empty-state" role="status"><strong>暂无匹配的 API Key</strong><p>调整筛选条件后重试，或清空筛选条件查看全部凭据。</p></div>
        <% else %>
          <div class="table-wrap"><div class="table-scroll" role="region" tabindex="0" aria-label="API Key 列表">
            <table class="api-keys-table"><caption class="sr-only">API Key 列表</caption><thead><tr><th scope="col">名称</th><th scope="col">密钥前缀</th><th scope="col">授权范围</th><th scope="col">创建时间</th><th scope="col">最近使用</th><th scope="col">到期时间</th><th scope="col">状态</th><th scope="col">操作</th></tr></thead><tbody>
              <%= for key <- filtered_rows(@api_key_rows, @api_key_query, @api_key_status) do %>
                <% revoked = not is_nil(key.revoked_at) %>
                <tr><td><div class="api-key-cell"><strong><%= key.name %></strong><small><%= key.id %></small></div></td><td><code>ks_live_<%= key.prefix %>_••••</code></td><td><div class="api-key-scopes"><%= for scope <- key.scopes do %><span class="badge badge-neutral"><%= scope %></span><% end %></div></td><td><%= format_datetime(key.created_at) %></td><td><%= format_datetime(key.last_used_at) %></td><td><%= format_datetime(key.expires_at) %></td><td><span class={if revoked, do: "status-badge status-badge--failure", else: "status-badge status-badge--success"}><%= if revoked, do: "已撤销", else: "有效" %></span></td><td class="table-actions"><button :if={!revoked and "api-key:rotate" in @permissions} type="button" class="button button-ghost refresh" phx-click="rotate-api-key" phx-value-id={key.id} phx-disable-with="轮换中…">轮换</button><button :if={!revoked and "api-key:revoke" in @permissions} type="button" class="button button-danger refresh danger-action" phx-confirm="确认撤销此 API Key 吗？" phx-click="revoke-api-key" phx-value-id={key.id} phx-disable-with="撤销中…">撤销</button></td></tr>
              <% end %>
            </tbody></table>
          </div></div>
        <% end %>
      </section>
    </div>
    """
  end

  def empty_form, do: %{"name" => "", "scopes" => "", "expiresAt" => ""}

  defp filtered_rows(rows, query, status) do
    normalized = String.downcase(String.trim(to_string(query)))

    Enum.filter(rows, fn key ->
      revoked = not is_nil(key.revoked_at)

      matches_status =
        status == "all" or (status == "revoked" and revoked) or
          (status == "active" and not revoked)

      haystack = Enum.join([key.name, key.prefix | key.scopes], " ") |> String.downcase()
      matches_status and (normalized == "" or String.contains?(haystack, normalized))
    end)
  end

  defp format_datetime(nil), do: "永不过期"
  defp format_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_datetime(value), do: to_string(value)
end
