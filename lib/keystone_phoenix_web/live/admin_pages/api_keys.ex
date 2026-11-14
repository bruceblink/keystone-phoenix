defmodule KeystonePhoenixWeb.Live.AdminPages.ApiKeys do
  @moduledoc "LiveView panel for API Key metadata and lifecycle operations."

  use Phoenix.Component

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
    <div class="panel api-key-panel">
      <div class="form-actions">
        <button :if={"api-key:create" in @permissions} type="button" class="refresh" phx-click="new-api-key" phx-disable-with="处理中…">签发 API Key</button>
        <button type="button" class="refresh secondary" phx-click="refresh-api-keys" phx-disable-with="刷新中…">刷新列表</button>
      </div>
      <%= if @api_key_feedback do %>
        <p id="api-key-feedback" class={Feedback.class(@api_key_feedback)} role={Feedback.role(@api_key_feedback)} aria-live={Feedback.live(@api_key_feedback)}><%= Feedback.message(@api_key_feedback) %></p>
      <% end %>
      <%= if @issued_api_key do %>
        <div id="api-key-secret" class="secret-banner" role="alert">
          <strong>请立即保存这枚 API Key</strong>
          <p>明文只在当前页面内存中展示一次。关闭提示后不会再次读取。</p>
          <code><%= @issued_api_key.api_key %></code>
          <button type="button" class="secondary" phx-click="dismiss-api-key-secret">关闭</button>
        </div>
      <% end %>
      <%= if @active_modal == "api-key" do %>
        <div class="modal-backdrop" role="presentation">
          <section id="api-key-modal" class="modal-panel" role="dialog" aria-modal="true" aria-labelledby="api-key-modal-title">
            <h3 id="api-key-modal-title">签发 API Key</h3>
            <p>API Key 只返回一次明文。请在签发成功后立即保存。</p>
            <form phx-submit="save-api-key" aria-describedby="api-key-feedback">
              <div class="form-grid">
                <div><label for="api-key-name">密钥名称</label><input id="api-key-name" name="name" value={@api_key_form["name"]} required /></div>
                <div><label for="api-key-expires">到期时间</label><input id="api-key-expires" type="datetime-local" name="expiresAt" value={@api_key_form["expiresAt"]} /></div>
                <div class="wide"><label for="api-key-scopes">授权范围</label><input id="api-key-scopes" name="scopes" value={@api_key_form["scopes"]} placeholder="user:read,role:read" required /></div>
              </div>
              <div class="form-actions"><button type="submit" phx-disable-with="签发中…">签发密钥</button><button type="button" class="secondary" phx-click="close-modal">取消</button></div>
            </form>
          </section>
        </div>
      <% end %>
      <form class="filter-bar" phx-submit="filter-api-keys">
        <label for="api-key-query">名称、前缀或范围</label>
        <input id="api-key-query" name="query" value={@api_key_query} placeholder="按名称、前缀或权限范围筛选" />
        <label for="api-key-status">状态</label>
        <select id="api-key-status" name="status"><option value="all" selected={@api_key_status == "all"}>全部状态</option><option value="active" selected={@api_key_status == "active"}>有效</option><option value="revoked" selected={@api_key_status == "revoked"}>已撤销</option></select>
        <button type="submit" class="secondary">查询</button>
      </form>
      <p :if={filtered_rows(@api_key_rows, @api_key_query, @api_key_status) == []} class="table-empty" role="status">暂无匹配的 API Key</p>
      <div :if={filtered_rows(@api_key_rows, @api_key_query, @api_key_status) != []} class="table-scroll" role="region" tabindex="0" aria-label="API Key 列表">
        <table><caption class="sr-only">API Key 列表</caption><thead><tr><th scope="col">名称</th><th scope="col">密钥前缀</th><th scope="col">授权范围</th><th scope="col">创建时间</th><th scope="col">最近使用</th><th scope="col">到期时间</th><th scope="col">状态</th><th scope="col">操作</th></tr></thead><tbody>
          <%= for key <- filtered_rows(@api_key_rows, @api_key_query, @api_key_status) do %>
            <% revoked = not is_nil(key.revoked_at) %>
            <tr><td><strong><%= key.name %></strong><small><%= key.id %></small></td><td><code>ks_live_<%= key.prefix %>_••••</code></td><td><%= Enum.join(key.scopes, ", ") %></td><td><%= format_datetime(key.created_at) %></td><td><%= format_datetime(key.last_used_at) %></td><td><%= format_datetime(key.expires_at) %></td><td><span class={if revoked, do: "status-badge status-badge--danger", else: "status-badge status-badge--success"}><%= if revoked, do: "已撤销", else: "有效" %></span></td><td class="table-actions"><button :if={!revoked and "api-key:rotate" in @permissions} type="button" class="refresh" phx-click="rotate-api-key" phx-value-id={key.id} phx-disable-with="轮换中…">轮换</button><button :if={!revoked and "api-key:revoke" in @permissions} type="button" class="refresh danger-action" phx-confirm="确认撤销此 API Key 吗？" phx-click="revoke-api-key" phx-value-id={key.id} phx-disable-with="撤销中…">撤销</button></td></tr>
          <% end %>
        </tbody></table>
      </div>
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
