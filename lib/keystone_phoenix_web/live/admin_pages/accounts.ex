defmodule KeystonePhoenixWeb.Live.AdminPages.Accounts do
  @moduledoc "LiveView panels for user accounts and personal settings."

  use Phoenix.Component

  import KeystonePhoenixWeb.Live.AdminPages.Pagination
  import KeystonePhoenixWeb.Live.AdminPages.Modal
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminPages.Status

  def users(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:active_modal, fn -> nil end)
      |> assign_new(:page_num, fn -> 1 end)
      |> assign_new(:page_size, fn -> 50 end)
      |> assign_new(:user_query, fn -> "" end)
      |> assign_new(:user_display_name_query, fn -> "" end)
      |> assign_new(:permissions, fn -> [] end)
      |> assign_new(:user_import_upload, fn -> nil end)
      |> assign_new(:user_import_result, fn -> nil end)
      |> assign_new(:selected_user_ids, fn -> [] end)

    ~H"""
    <div class="panel users-page">
      <div class="page-heading">
        <div>
          <p class="eyebrow">IDENTITY / USERS</p>
          <h1>用户管理</h1>
          <p class="page-description">查询用户身份、组织归属和授权角色。新增和编辑在模态框中完成。</p>
        </div>
        <div class="heading-actions form-actions">
          <button :if={!@read_only and "user:delete" in @permissions} type="button" class="button button-danger refresh danger-action" phx-click="delete-users" phx-value-user-ids={Enum.join(@selected_user_ids, ",")} phx-confirm="确认删除选中的用户吗？" disabled={@selected_user_ids == []} phx-disable-with="删除中…">删除用户（<%= length(@selected_user_ids) %>）</button>
          <button :if={!@read_only and "user:import" in @permissions} type="button" class="button button-secondary refresh secondary" phx-click="new-user-import" phx-disable-with="处理中…">导入 Excel</button>
          <button :if={!@read_only} type="button" class="button button-primary refresh" phx-click="new-user" phx-disable-with="处理中…">新建用户</button>
          <button type="button" class="button button-secondary refresh secondary" phx-click="refresh-users" phx-disable-with="刷新中…">刷新用户</button>
          <button :if={"user:export" in @permissions} type="button" class="button button-secondary refresh secondary" phx-click="export-users" phx-disable-with="导出中…">导出 XLSX</button>
        </div>
      </div>
      <section class="card filter-card users-filter-card" aria-labelledby="users-filter-title">
        <div class="card-header">
          <div>
            <h2 id="users-filter-title">筛选用户</h2>
            <p>按用户名或昵称缩小当前列表。</p>
          </div>
        </div>
        <form class="filter-form users-filter-form" phx-submit="filter-users">
          <label for="user-query">用户名</label>
          <input id="user-query" name="username" value={@user_query} placeholder="按用户名筛选" autocomplete="off" />
          <label for="user-display-name-query">昵称</label>
          <input id="user-display-name-query" name="displayName" value={@user_display_name_query} placeholder="按昵称筛选" autocomplete="off" />
          <div class="form-actions users-filter-actions">
            <button type="submit" class="button button-primary refresh" phx-disable-with="查询中…">查询</button>
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
          <div><label for="user-nickname">昵称</label><input id="user-nickname" name="nickname" value={@user_form["nickname"] || ""} required /></div>
          <div><label for="user-password">密码（新建时必填）</label><input id="user-password" type="password" name="password" value={@user_form["password"] || ""} /></div>
          <div><label for="user-email">邮箱</label><input id="user-email" type="email" name="email" value={@user_form["email"] || ""} /></div>
          <div><label for="user-phone">手机号</label><input id="user-phone" name="phoneNumber" value={@user_form["phoneNumber"] || ""} /></div>
          <div><label for="user-sex">性别</label><select id="user-sex" name="sex"><option value="0" selected={@user_form["sex"] in [0, "0"]}>男</option><option value="1" selected={@user_form["sex"] in [1, "1"]}>女</option><option value="2" selected={@user_form["sex"] in [2, "2"]}>未知</option></select></div>
          <div><label for="user-dept">部门</label><select id="user-dept" name="deptId"><option value="">未分配</option><%= for dept <- @dept_rows do %><option value={dept["deptId"]} selected={to_string(@user_form["deptId"] || "") == to_string(dept["deptId"])}><%= dept["deptName"] %></option><% end %></select></div>
          <div><label for="user-post">岗位</label><select id="user-post" name="postId"><option value="">未分配</option><%= for post <- @post_rows do %><option value={post["postId"]} selected={to_string(@user_form["postId"] || "") == to_string(post["postId"])}><%= post["postName"] %></option><% end %></select></div>
          <div><label for="user-role">角色</label><select id="user-role" name="roleId"><option value="">未分配</option><%= for role <- @role_rows do %><option value={role["roleId"]} selected={to_string(@user_form["roleId"] || "") == to_string(role["roleId"])}><%= role["roleName"] %></option><% end %></select></div>
          <div><label for="user-status">状态</label><select id="user-status" name="status"><option value="1" selected={@user_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@user_form["status"] in [0, "0"]}>停用</option></select></div>
          <div class="wide"><label for="user-remark">备注</label><textarea id="user-remark" name="remark"><%= @user_form["remark"] || "" %></textarea></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存用户</button><button :if={@user_form["userId"] != ""} type="button" class="secondary" phx-click="close-modal" phx-value-modal="user" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
      <form :if={!@read_only and @user_form["userId"] != ""} id="user-reset-password-form" aria-describedby="user-feedback" phx-submit="reset-user-password">
        <input type="hidden" name="userId" value={@user_form["userId"]} />
        <div class="form-grid">
          <div><label for="user-reset-password">重置密码</label><input id="user-reset-password" type="password" name="password" minlength="8" required /></div>
        </div>
        <div class="form-actions"><button type="submit" class="secondary" phx-disable-with="重置中…">重置用户密码</button></div>
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
        <div class="card-header">
          <div>
            <h2 id="users-table-title">用户列表</h2>
            <p>当前加载 <%= length(@user_rows) %> 个用户。</p>
          </div>
          <span class="badge badge-info">LiveView</span>
        </div>
        <div :if={@user_rows == []} class="users-empty empty-state" role="status"><strong>没有匹配的用户</strong><p>暂无用户数据。调整筛选条件后重试，或清空筛选条件查看全部用户。</p></div>
        <div class="table-wrap">
          <div class="table-scroll" role="region" tabindex="0" aria-label="用户列表"><table class="users-table"><caption class="sr-only">用户列表</caption>
            <% page_user_rows = page_rows(@user_rows, @page_num, @page_size) %>
            <% all_selected = page_user_rows != [] and Enum.all?(page_user_rows, &(to_string(&1["userId"]) in @selected_user_ids)) %>
            <thead><tr><th scope="col"><input type="checkbox" aria-label="选择当前页用户" checked={all_selected} phx-click="toggle-all-user-selection" phx-value-selected={if all_selected, do: "false", else: "true"} /></th><th scope="col">用户名</th><th scope="col">UUID</th><th scope="col">部门</th><th scope="col">岗位</th><th scope="col">角色</th><th scope="col">状态</th><th scope="col">操作</th></tr></thead>
            <tbody>
              <%= for user <- page_user_rows do %>
                <tr>
                  <td><input type="checkbox" aria-label={"选择用户 #{user["username"]}"} checked={to_string(user["userId"]) in @selected_user_ids} phx-click="toggle-user-selection" phx-value-user-id={user["userId"]} phx-value-selected={if to_string(user["userId"]) in @selected_user_ids, do: "false", else: "true"} /></td><td><div class="user-cell"><span class="user-cell-avatar"><%= String.first(user["nickname"] || user["username"] || "U") %></span><span><strong><%= user["nickname"] || "" %></strong><small><%= user["username"] %></small></span></div></td><td><code class="user-uuid"><%= user["userId"] %></code></td><td><%= user["deptName"] || "" %></td><td><%= user["postName"] || "" %></td><td><%= user["roleName"] || "" %></td><td><span class={"status-badge #{Status.normal_paused(user["status"])}"}><%= if user["status"] == 1, do: "正常", else: "停用" %></span></td>
                  <td :if={!@read_only} class="table-actions"><button type="button" class="button button-ghost refresh" phx-click="edit-user" phx-value-user-id={user["userId"]} phx-disable-with="加载中…">编辑</button><button type="button" class="button button-ghost refresh" phx-click="toggle-user-status" phx-value-user-id={user["userId"]} phx-value-status={if user["status"] == 1, do: 0, else: 1} phx-disable-with="处理中…"><%= if user["status"] == 1, do: "停用", else: "启用" %></button><button type="button" class="button button-danger refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-user" phx-value-user-id={user["userId"]} phx-disable-with="删除中…">删除</button></td>
                </tr>
              <% end %>
            </tbody>
          </table></div>
        </div>
        <div class="table-card-footer">
          <.pagination panel="users" page_num={min(@page_num, page_count(length(@user_rows), @page_size))} page_size={@page_size} total={length(@user_rows)} />
        </div>
      </section>
    </div>
    """
  end

  def profile(assigns) do
    assigns = assign_new(assigns, :avatar_upload, fn -> nil end)

    ~H"""
    <div class="panel profile-page">
      <div class="page-heading">
        <div>
          <p class="eyebrow">ACCOUNT / PROFILE</p>
          <h1>个人资料</h1>
          <p class="page-description">维护当前账号资料、头像和登录凭据。</p>
        </div>
      </div>
      <%= if @profile_feedback do %><p id="profile-feedback" class={Feedback.class(@profile_feedback)} role={Feedback.role(@profile_feedback)} aria-live={Feedback.live(@profile_feedback)}><%= Feedback.message(@profile_feedback) %></p><% end %>
      <section class="card profile-card" aria-labelledby="profile-details-title">
        <div class="card-header"><div><h2 id="profile-details-title">账号资料</h2><p>更新昵称、联系方式和性别信息。</p></div></div>
      <form aria-describedby="profile-feedback" phx-submit="save-profile">
        <div class="form-grid">
          <div><label for="profile-nickname">昵称</label><input id="profile-nickname" name="nickname" value={@profile_form["nickname"] || ""} required /></div>
          <div><label for="profile-email">邮箱</label><input id="profile-email" type="email" name="email" value={@profile_form["email"] || ""} /></div>
          <div><label for="profile-phone">手机号</label><input id="profile-phone" name="phoneNumber" value={@profile_form["phoneNumber"] || ""} /></div>
          <div><label for="profile-sex">性别</label><select id="profile-sex" name="sex"><option value="0" selected={@profile_form["sex"] in [0, "0"]}>男</option><option value="1" selected={@profile_form["sex"] in [1, "1"]}>女</option><option value="2" selected={@profile_form["sex"] in [2, "2"]}>未知</option></select></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存资料</button></div>
      </form>
      <form aria-describedby="profile-feedback" phx-submit="update-profile-avatar">
        <label for="profile-avatar">头像地址</label><input id="profile-avatar" name="avatar" value={@profile_form["avatar"] || ""} placeholder="https://..." />
        <div class="form-actions"><button type="submit" class="secondary" phx-disable-with="更新中…">更新头像</button></div>
      </form>
      <%= if @avatar_upload do %>
        <form id="profile-avatar-upload-form" aria-describedby="profile-feedback" phx-submit="save-profile-avatar-upload">
          <label for="profile-avatar-file">头像文件</label>
          <.live_file_input upload={@avatar_upload} id="profile-avatar-file" />
          <%= for entry <- @avatar_upload.entries do %>
            <progress value={entry.progress} max="100"><%= entry.progress %>%</progress>
          <% end %>
          <%= for entry <- @avatar_upload.errors do %>
            <p class="error" role="alert">头像文件无效：<%= upload_error_message(entry) %></p>
          <% end %>
          <div class="form-actions"><button type="submit" class="secondary" phx-disable-with="上传中…">上传头像</button></div>
        </form>
      <% end %>
      </section>
      <section class="card profile-card" aria-labelledby="profile-password-title">
        <div class="card-header"><div><h2 id="profile-password-title">修改密码</h2><p>使用当前密码确认账号变更。</p></div></div>
      <form aria-describedby="profile-feedback" phx-submit="change-profile-password">
        <div class="form-grid">
          <div><label for="profile-old-password">当前密码</label><input id="profile-old-password" type="password" name="oldPassword" required /></div>
          <div><label for="profile-new-password">新密码</label><input id="profile-new-password" type="password" name="newPassword" required /></div>
        </div>
        <div class="form-actions"><button type="submit" class="secondary" phx-disable-with="更新中…">更新密码</button></div>
      </form>
      </section>
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
