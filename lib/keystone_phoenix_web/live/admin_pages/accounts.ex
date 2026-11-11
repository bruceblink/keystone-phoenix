defmodule KeystonePhoenixWeb.Live.AdminPages.Accounts do
  @moduledoc "LiveView panels for user accounts and personal settings."

  use Phoenix.Component

  import KeystonePhoenixWeb.Live.AdminPages.Pagination
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminPages.Status
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def users(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:page_num, fn -> 1 end)
      |> assign_new(:page_size, fn -> 50 end)

    ~H"""
    <div class="panel">
      <div class="form-actions">
        <button :if={!@read_only} type="button" class="refresh" phx-click="new-user" phx-disable-with="处理中…">新建用户</button>
        <button type="button" class="refresh secondary" phx-click="refresh-users" phx-disable-with="刷新中…">刷新用户</button>
      </div>
      <%= if @user_feedback do %>
        <p id="user-feedback" class={Feedback.class(@user_feedback)} role={Feedback.role(@user_feedback)} aria-live={Feedback.live(@user_feedback)}><%= Feedback.message(@user_feedback) %></p>
      <% end %>
      <p :if={@user_rows == []} class="table-empty" role="status">暂无用户数据</p>
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
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存用户</button><button :if={@user_form["userId"] != ""} type="button" class="secondary" phx-click="new-user" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
      <form :if={!@read_only and @user_form["userId"] != ""} id="user-reset-password-form" aria-describedby="user-feedback" phx-submit="reset-user-password">
        <input type="hidden" name="userId" value={@user_form["userId"]} />
        <div class="form-grid">
          <div><label for="user-reset-password">重置密码</label><input id="user-reset-password" type="password" name="password" minlength="8" required /></div>
        </div>
        <div class="form-actions"><button type="submit" class="secondary" phx-disable-with="重置中…">重置用户密码</button></div>
      </form>
      <div class="table-scroll" role="region" tabindex="0" aria-label="用户列表"><table><caption class="sr-only">用户列表</caption>
        <thead><tr><th scope="col">用户名</th><th scope="col">昵称</th><th scope="col">部门</th><th scope="col">角色</th><th scope="col">邮箱</th><th scope="col">手机号</th><th scope="col">状态</th><th scope="col">操作</th></tr></thead>
        <tbody>
          <%= for user <- Support.page_rows(@user_rows, @page_num, @page_size) do %>
            <tr>
              <td><%= user["username"] %></td><td><%= user["nickname"] %></td><td><%= user["deptName"] || "" %></td><td><%= user["roleName"] || "" %></td><td><%= user["email"] || "" %></td><td><%= user["phoneNumber"] || "" %></td><td><span class={"status-badge #{Status.normal_paused(user["status"])}"}><%= if user["status"] == 1, do: "正常", else: "停用" %></span></td>
              <td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="edit-user" phx-value-user-id={user["userId"]} phx-disable-with="加载中…">编辑</button><button type="button" class="refresh" phx-click="toggle-user-status" phx-value-user-id={user["userId"]} phx-value-status={if user["status"] == 1, do: 0, else: 1} phx-disable-with="处理中…"><%= if user["status"] == 1, do: "停用", else: "启用" %></button><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-user" phx-value-user-id={user["userId"]} phx-disable-with="删除中…">删除</button></td>
            </tr>
          <% end %>
        </tbody>
      </table></div>
      <.pagination panel="users" page_num={min(@page_num, page_count(length(@user_rows), @page_size))} page_size={@page_size} total={length(@user_rows)} />
    </div>
    """
  end

  def profile(assigns) do
    assigns = assign_new(assigns, :avatar_upload, fn -> nil end)

    ~H"""
    <div class="panel">
      <h3>个人资料</h3>
      <%= if @profile_feedback do %><p id="profile-feedback" class={Feedback.class(@profile_feedback)} role={Feedback.role(@profile_feedback)} aria-live={Feedback.live(@profile_feedback)}><%= Feedback.message(@profile_feedback) %></p><% end %>
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
      <h3>修改密码</h3>
      <form aria-describedby="profile-feedback" phx-submit="change-profile-password">
        <div class="form-grid">
          <div><label for="profile-old-password">当前密码</label><input id="profile-old-password" type="password" name="oldPassword" required /></div>
          <div><label for="profile-new-password">新密码</label><input id="profile-new-password" type="password" name="newPassword" required /></div>
        </div>
        <div class="form-actions"><button type="submit" class="secondary" phx-disable-with="更新中…">更新密码</button></div>
      </form>
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
end
