defmodule KeystonePhoenixWeb.Live.AdminPages.Accounts do
  @moduledoc "LiveView panels for user accounts and personal settings."

  use Phoenix.Component

  import KeystonePhoenixWeb.Live.AdminPages.Pagination
  import KeystonePhoenixWeb.Live.AdminPages.Modal
  import KeystonePhoenixWeb.Live.AdminPages.ListToolbar
  import KeystonePhoenixWeb.Live.AdminPages.Navigation, only: [nav_icon: 1]
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminPages.Status

  def users(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:active_modal, fn -> nil end)
      |> assign_new(:page_num, fn -> 1 end)
      |> assign_new(:page_size, fn -> 50 end)
      |> assign_new(:user_total, fn -> length(assigns[:user_rows] || []) end)
      |> assign_new(:users_server_paged, fn -> false end)
      |> assign_new(:user_query, fn -> "" end)
      |> assign_new(:user_display_name_query, fn -> "" end)
      |> assign_new(:role_rows, fn -> [] end)
      |> assign_new(:permissions, fn -> [] end)
      |> assign_new(:user_import_upload, fn -> nil end)
      |> assign_new(:user_import_result, fn -> nil end)
      |> assign_new(:selected_user_ids, fn -> [] end)

    ~H"""
    <div class="users-page">
      <!-- 用户列表沿用 admin-web 的筛选卡、批量操作和统一表格结构。 -->
      <div class="page-heading">
        <div>
          <p class="eyebrow">IDENTITY / USERS</p>
          <h1>用户管理</h1>
          <p class="page-description">查询用户身份、组织归属和授权角色。新增和编辑在模态框中完成。</p>
        </div>
      </div>
      <section class="card users-filter-card" aria-labelledby="users-filter-title">
        <form class="filter-form users-filter-form" phx-submit="filter-users">
          <label for="user-query"><span>用户名</span><input id="user-query" name="username" value={@user_query} placeholder="按用户名筛选" autocomplete="off" /></label>
          <label for="user-display-name-query"><span>展示名</span><input id="user-display-name-query" name="displayName" value={@user_display_name_query} placeholder="按展示名筛选" autocomplete="off" /></label>
          <div class="users-filter-actions">
            <button type="submit" class="button button-primary refresh" phx-disable-with="查询中…"><.nav_icon name="search" />查询</button>
            <button type="button" class="button button-ghost refresh secondary" phx-click="reset-user-filter" phx-disable-with="处理中…">重置</button>
          </div>
        </form>
      </section>
      <%= if @user_feedback do %>
        <p id="user-feedback" class={Feedback.class(@user_feedback)} role={Feedback.role(@user_feedback)} aria-live={Feedback.live(@user_feedback)}><%= Feedback.message(@user_feedback) %></p>
      <% end %>
      <%= if @active_modal == "user" do %>
        <.modal id="user-modal" title={if @user_form["userId"] == "", do: "新建用户", else: "编辑用户"} description="维护账号资料、组织归属和登录权限。">
      <form :if={!@read_only} aria-describedby="user-feedback" phx-submit="save-user">
        <input type="hidden" name="userId" value={@user_form["userId"]} />
        <div class="form-grid">
          <div><label for="user-username">用户名</label><input id="user-username" name="username" value={@user_form["username"] || ""} required /></div>
          <div><label for="user-password">初始密码</label><input id="user-password" type="password" name="password" value={@user_form["password"] || ""} placeholder={if @user_form["userId"] == "", do: "至少 12 位", else: "留空表示不修改"} /></div>
          <div><label for="user-nickname">展示名 *</label><input id="user-nickname" name="nickname" value={@user_form["nickname"] || ""} required /></div>
          <div><label for="user-dept">部门 UUID</label><input id="user-dept" name="deptId" value={@user_form["deptId"] || ""} placeholder="可选" /></div>
          <div><label for="user-post">岗位 UUID</label><input id="user-post" name="postId" value={@user_form["postId"] || ""} placeholder="可选" /></div>
          <div><label for="user-email">邮箱</label><input id="user-email" type="email" name="email" value={@user_form["email"] || ""} /></div>
          <div><label for="user-phone">联系电话</label><input id="user-phone" name="phoneNumber" value={@user_form["phoneNumber"] || ""} /></div>
          <fieldset class="wide user-role-picker"><legend>角色</legend><input type="hidden" name="roleCodes[]" value="" /><div class="user-role-options"><%= for role <- enabled_roles(@role_rows) do %><% role_code = role_code(role) %><label class="checkbox-label"><input type="checkbox" name="roleCodes[]" value={role_code} checked={role_code_selected?(@user_form["roleCodes"], role_code)} /><span><%= role["roleName"] || role["name"] || role_code %></span><code><%= role_code %></code></label><% end %></div><p :if={enabled_roles(@role_rows) == []} class="form-help" role="status">没有可选择的启用角色。</p><small>角色来自当前账号可配置的启用角色；未选择角色会清空用户角色。</small></fieldset>
          <div class="wide"><label for="user-remark">备注</label><textarea id="user-remark" name="remark"><%= @user_form["remark"] || "" %></textarea></div>
        </div>
        <div class="form-options"><label><input type="checkbox" name="enabled" checked={@user_form["enabled"] in [true, 1, "1", "on"]} />账号启用</label><label :if={@user_form["userId"] != ""}><input type="checkbox" name="clearDept" checked={@user_form["clearDept"] in [true, 1, "1", "on"]} />清除部门归属</label></div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存用户</button><button :if={@user_form["userId"] != ""} type="button" class="secondary" phx-click="close-modal" phx-value-modal="user" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
        </.modal>
      <% end %>
      <%= if @active_modal == "user-import" and @user_import_upload do %>
        <.modal id="user-import-modal" title="导入用户" description="上传 Excel Open XML 工作簿。按行校验后返回成功和失败结果。">
          <form id="user-import-form" aria-describedby="user-feedback" phx-submit="import-users">
            <label for="user-import-file">用户导入文件</label>
            <.live_file_input upload={@user_import_upload} id="user-import-file" />
            <%= for entry <- @user_import_upload.entries do %>
              <progress value={entry.progress} max="100"><%= entry.progress %>%</progress>
            <% end %>
            <%= for entry <- @user_import_upload.errors do %>
              <p class="error" role="alert">用户导入文件无效：<%= user_import_error_message(entry) %></p>
            <% end %>
            <%= if @user_import_result do %>
              <section class="user-import-result" aria-label="导入结果">
                <div class="user-import-summary"><span><strong><%= @user_import_result["success"] %></strong><small>成功</small></span><span><strong><%= length(@user_import_result["failed"]) %></strong><small>失败</small></span><span><strong><%= @user_import_result["total"] %></strong><small>总行数</small></span></div>
                <p :if={@user_import_result["failed"] == []} class="feedback">全部数据已成功导入。</p>
                <div :if={@user_import_result["failed"] != []} class="user-import-failures">
                  <h3>失败行</h3>
                  <div class="user-import-failures-wrap" role="region" tabindex="0" aria-label="用户导入失败明细">
                    <table class="user-import-failures-table">
                      <caption class="sr-only">用户导入失败明细</caption>
                      <thead><tr><th scope="col">行号</th><th scope="col">用户名</th><th scope="col">原因</th></tr></thead>
                      <tbody>
                        <%= for failure <- @user_import_result["failed"] do %>
                          <tr><td><%= failure["row"] %></td><td><%= failure["username"] || "—" %></td><td><%= failure["reason"] %></td></tr>
                        <% end %>
                      </tbody>
                    </table>
                  </div>
                </div>
              </section>
            <% else %>
              <p class="muted">导入要求当前登录会话完成 AAL2 验证。</p>
            <% end %>
            <div class="form-actions"><button type="submit" class="button button-primary" phx-disable-with="导入中…">开始导入</button><button type="button" class="button button-ghost secondary" phx-click="close-modal">关闭</button></div>
          </form>
        </.modal>
      <% end %>
      <%= if @user_import_upload && "user:import" in @permissions do %>
        <span id="user-import-upload-hook" hidden></span>
      <% end %>
      <span id="user-download-hook" phx-hook="DownloadFile" hidden></span>
      <section class="card table-card users-table-card" aria-labelledby="users-table-title">
        <.list_toolbar label="用户列表操作">
          <button :if={!@read_only} type="button" class="button button-primary refresh" phx-click="new-user" phx-disable-with="处理中…"><.nav_icon name="plus" />新增用户</button>
          <button :if={!@read_only and "user:import" in @permissions} type="button" class="button button-secondary refresh secondary" phx-click="new-user-import" phx-disable-with="处理中…"><.nav_icon name="upload" />导入 Excel</button>
          <button :if={"user:export" in @permissions} type="button" class="button button-secondary refresh secondary" phx-click="export-users" phx-disable-with="导出中…"><.nav_icon name="download" />导出 Excel</button>
          <button :if={!@read_only and "user:delete" in @permissions} type="button" class="button button-danger refresh danger-action" phx-click="delete-users" phx-value-user-ids={Enum.join(@selected_user_ids, ",")} phx-confirm="确认删除选中的用户吗？" disabled={@selected_user_ids == []} phx-disable-with="删除中…">删除用户（<%= length(@selected_user_ids) %>）</button>
          <button type="button" class="button button-secondary refresh secondary" phx-click="refresh-users" phx-disable-with="刷新中…"><.nav_icon name="refresh" />刷新列表</button>
        </.list_toolbar>
        <div class="card-header">
          <div>
            <h2 id="users-table-title">用户列表</h2>
            <p>共 <%= @user_total %> 个用户</p>
          </div>
          <span class="badge badge-info">系统 API</span>
        </div>
        <% page_user_rows = if @users_server_paged, do: @user_rows, else: page_rows(@user_rows, @page_num, @page_size) %>
        <%= if page_user_rows == [] do %>
          <div class="users-empty" role="status"><span class="users-empty-icon" aria-hidden="true"><.nav_icon name="users" /></span><strong>没有匹配的用户</strong><p>调整筛选条件后重试，或清空筛选条件查看全部用户。</p></div>
        <% else %>
          <div class="users-table-wrap" role="region" tabindex="0" aria-label="用户列表"><table class="users-table"><caption class="sr-only">用户列表</caption>
              <% all_selected = Enum.all?(page_user_rows, &(to_string(&1["userId"]) in @selected_user_ids)) %>
              <thead><tr><th scope="col"><input type="checkbox" aria-label="选择当前页用户" checked={all_selected} phx-click="toggle-all-user-selection" phx-value-selected={if all_selected, do: "false", else: "true"} /></th><th scope="col">用户</th><th scope="col">UUID</th><th scope="col">部门</th><th scope="col">岗位</th><th scope="col">角色</th><th scope="col">状态</th><th scope="col">操作</th></tr></thead>
              <tbody>
                <%= for user <- page_user_rows do %>
                  <tr>
                    <td><input type="checkbox" aria-label={"选择用户 #{user["username"]}"} checked={to_string(user["userId"]) in @selected_user_ids} phx-click="toggle-user-selection" phx-value-user-id={user["userId"]} phx-value-selected={if to_string(user["userId"]) in @selected_user_ids, do: "false", else: "true"} /></td><td><div class="user-cell"><span class="user-cell-avatar"><%= String.first(user["nickname"] || user["username"] || "U") %></span><span><strong><%= user["nickname"] || "" %></strong><small><%= user["username"] %></small></span></div></td><td><code class="user-uuid"><%= user["userId"] %></code></td><td><%= user["deptName"] || "" %></td><td><%= user["postName"] || "" %></td><td><%= user["roleName"] || "" %></td><td><span class={"status-badge #{Status.normal_paused(user["status"])}"}><%= if user["status"] == 1, do: "正常", else: "停用" %></span></td>
                    <td :if={!@read_only} class="table-actions"><button type="button" class="button button-ghost refresh" phx-click="edit-user" phx-value-user-id={user["userId"]} phx-disable-with="加载中…">编辑</button></td>
                  </tr>
                <% end %>
              </tbody>
            </table></div>
        <% end %>
        <div class="table-card-footer">
          <.pagination panel="users" page_num={@page_num} page_size={@page_size} total={@user_total} />
        </div>
      </section>
    </div>
    """
  end

  defp enabled_roles(roles),
    do:
      Enum.filter(
        List.wrap(roles),
        &(&1["status"] in [1, "1", true] or &1["enabled"] in [1, "1", true])
      )

  defp role_code(role), do: to_string(role["roleKey"] || role["code"] || "")

  defp role_code_selected?(value, code) do
    value
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.member?(code)
  end

  def profile(assigns) do
    assigns = assign_new(assigns, :profile_loaded, fn -> true end)

    ~H"""
    <div class="profile-page">
      <!-- 个人资料只从顶栏头像进入，资料和密码保持两个独立卡片。 -->
      <div class="page-heading">
        <div>
          <p class="eyebrow">ACCOUNT / PROFILE</p>
          <h1>个人资料</h1>
          <p class="page-description">维护当前账号资料和登录凭据。</p>
        </div>
        <div class="heading-actions"><button type="button" class="button button-secondary refresh" phx-click="show-panel" phx-value-panel="profile" phx-disable-with="刷新中…">刷新资料</button></div>
      </div>
      <p :if={@profile_feedback && !@profile_loaded} id="profile-feedback" class={Feedback.class(@profile_feedback)} role={Feedback.role(@profile_feedback)} aria-live={Feedback.live(@profile_feedback)}><%= Feedback.message(@profile_feedback) %><small :if={Feedback.code(@profile_feedback)}>错误码：<%= Feedback.code(@profile_feedback) %></small></p>
      <%= if @profile_loaded do %>
        <section class="card profile-card" aria-labelledby="profile-details-title">
          <div class="card-header"><div><h2 id="profile-details-title">基本资料</h2><p>这些字段会保存到当前账号。</p></div><span class="badge badge-info">系统 API</span></div>
          <form id="profile-form" class="admin-form" aria-describedby={if @profile_feedback, do: "profile-feedback", else: nil} phx-submit="save-profile">
            <p :if={@profile_feedback} id="profile-feedback" class={Feedback.class(@profile_feedback)} role={Feedback.role(@profile_feedback)} aria-live={Feedback.live(@profile_feedback)}><%= Feedback.message(@profile_feedback) %><small :if={Feedback.code(@profile_feedback)}>错误码：<%= Feedback.code(@profile_feedback) %></small></p>
            <label><span>用户名</span><input id="profile-username" value={@profile_form["username"] || ""} readonly /></label>
            <label><span>展示名 *</span><input id="profile-nickname" name="nickname" value={@profile_form["nickname"] || @profile_form["displayName"] || ""} aria-describedby={if @profile_feedback, do: "profile-feedback", else: nil} required /></label>
            <label><span>邮箱</span><input id="profile-email" type="email" name="email" value={@profile_form["email"] || ""} /></label>
            <label><span>联系电话</span><input id="profile-phone" name="phoneNumber" value={@profile_form["phoneNumber"] || ""} /></label>
            <label><span>头像地址</span><input id="profile-avatar" name="avatar" value={@profile_form["avatar"] || ""} placeholder="https://..." /></label>
            <label><span>性别</span><select id="profile-sex" name="sex"><option value="" selected={@profile_form["sex"] in [nil, 2, "2", ""]}>未知</option><option value="1" selected={@profile_form["sex"] in [1, "1"]}>男</option><option value="0" selected={@profile_form["sex"] in [0, "0"]}>女</option></select></label>
            <div class="modal-footer"><button type="submit" class="button button-primary" phx-disable-with="保存中…">保存资料</button></div>
          </form>
        </section>
        <section class="card profile-card" aria-labelledby="profile-password-title">
          <div class="card-header"><div><h2 id="profile-password-title">修改密码</h2><p>账号要求 MFA 时，更新密码前需完成二次验证。</p></div></div>
          <form class="admin-form" aria-describedby="profile-feedback" phx-submit="change-profile-password">
            <label><span>新密码 *</span><input id="profile-password" type="password" name="password" autocomplete="new-password" required /></label>
            <div class="modal-footer"><button type="submit" class="button button-secondary" phx-disable-with="更新中…">更新密码</button></div>
          </form>
        </section>
      <% end %>
    </div>
    """
  end

  def upload_error_message(:too_large), do: "文件不能超过 50 MB"
  def upload_error_message(:not_accepted), do: "只支持 BMP、GIF、JPG、JPEG、PNG 或 WEBP 图片"
  def upload_error_message(:too_many_files), do: "一次只能上传一个头像文件"
  def upload_error_message(:external_client_failure), do: "上传连接失败，请重试"
  def upload_error_message({:writer_failure, _reason}), do: "头像文件保存失败"
  def upload_error_message({:external_metadata_failure, _reason}), do: "上传准备失败，请重试"
  def upload_error_message(_reason), do: "头像文件无效，请重试"

  def user_import_error_message(:too_large), do: "文件不能超过 50 MB"
  def user_import_error_message(:not_accepted), do: "只支持 XLSX 文件"
  def user_import_error_message(:too_many_files), do: "一次只能上传一个用户导入文件"
  def user_import_error_message(_reason), do: "用户导入文件无效，请重试"
end
