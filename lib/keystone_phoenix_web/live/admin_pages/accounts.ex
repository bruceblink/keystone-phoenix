defmodule KeystonePhoenixWeb.Live.AdminPages.Accounts do
  @moduledoc "LiveView panels for user accounts and personal settings."

  use Phoenix.Component

  def users(assigns) do
    assigns = assign_new(assigns, :read_only, fn -> false end)

    ~H"""
    <div class="panel">
      <div class="form-actions">
        <button :if={!@read_only} type="button" class="refresh" phx-click="new-user">新建用户</button>
        <button type="button" class="refresh secondary" phx-click="refresh-users">刷新用户</button>
      </div>
      <%= if @user_feedback do %>
        <p class="feedback" role="status"><%= @user_feedback %></p>
      <% end %>
      <form :if={!@read_only} phx-submit="save-user">
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
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存用户</button><button :if={@user_form["userId"] != ""} type="button" class="secondary" phx-click="new-user">取消编辑</button></div>
      </form>
      <form :if={!@read_only and @user_form["userId"] != ""} id="user-reset-password-form" phx-submit="reset-user-password">
        <input type="hidden" name="userId" value={@user_form["userId"]} />
        <div class="form-grid">
          <div><label for="user-reset-password">重置密码</label><input id="user-reset-password" type="password" name="password" minlength="8" required /></div>
        </div>
        <div class="form-actions"><button type="submit" class="secondary" phx-disable-with="重置中…">重置用户密码</button></div>
      </form>
      <table>
        <thead><tr><th>用户名</th><th>昵称</th><th>部门</th><th>角色</th><th>邮箱</th><th>手机号</th><th>状态</th><th>操作</th></tr></thead>
        <tbody>
          <%= for user <- @user_rows do %>
            <tr>
              <td><%= user["username"] %></td><td><%= user["nickname"] %></td><td><%= user["deptName"] || "" %></td><td><%= user["roleName"] || "" %></td><td><%= user["email"] || "" %></td><td><%= user["phoneNumber"] || "" %></td><td><%= if user["status"] == 1, do: "正常", else: "停用" %></td>
              <td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="edit-user" phx-value-user-id={user["userId"]}>编辑</button><button type="button" class="refresh" phx-click="toggle-user-status" phx-value-user-id={user["userId"]} phx-value-status={if user["status"] == 1, do: 0, else: 1}><%= if user["status"] == 1, do: "停用", else: "启用" %></button><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-user" phx-value-user-id={user["userId"]}>删除</button></td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  def profile(assigns) do
    assigns = assign_new(assigns, :avatar_upload, fn -> nil end)

    ~H"""
    <div class="panel">
      <h3>个人资料</h3>
      <%= if @profile_feedback do %><p class="feedback" role="status"><%= @profile_feedback %></p><% end %>
      <form phx-submit="save-profile">
        <div class="form-grid">
          <div><label for="profile-nickname">昵称</label><input id="profile-nickname" name="nickname" value={@profile_form["nickname"] || ""} required /></div>
          <div><label for="profile-email">邮箱</label><input id="profile-email" type="email" name="email" value={@profile_form["email"] || ""} /></div>
          <div><label for="profile-phone">手机号</label><input id="profile-phone" name="phoneNumber" value={@profile_form["phoneNumber"] || ""} /></div>
          <div><label for="profile-sex">性别</label><select id="profile-sex" name="sex"><option value="0" selected={@profile_form["sex"] in [0, "0"]}>男</option><option value="1" selected={@profile_form["sex"] in [1, "1"]}>女</option><option value="2" selected={@profile_form["sex"] in [2, "2"]}>未知</option></select></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存资料</button></div>
      </form>
      <form phx-submit="update-profile-avatar">
        <label for="profile-avatar">头像地址</label><input id="profile-avatar" name="avatar" value={@profile_form["avatar"] || ""} placeholder="https://..." />
        <div class="form-actions"><button type="submit" class="secondary" phx-disable-with="更新中…">更新头像</button></div>
      </form>
      <%= if @avatar_upload do %>
        <form id="profile-avatar-upload-form" phx-submit="save-profile-avatar-upload">
          <label for="profile-avatar-file">头像文件</label>
          <.live_file_input upload={@avatar_upload} id="profile-avatar-file" />
          <%= for entry <- @avatar_upload.entries do %>
            <progress value={entry.progress} max="100"><%= entry.progress %>%</progress>
          <% end %>
          <%= for entry <- @avatar_upload.errors do %>
            <p class="error" role="alert">头像文件无效：<%= inspect(entry) %></p>
          <% end %>
          <div class="form-actions"><button type="submit" class="secondary" phx-disable-with="上传中…">上传头像</button></div>
        </form>
      <% end %>
      <h3>修改密码</h3>
      <form phx-submit="change-profile-password">
        <div class="form-grid">
          <div><label for="profile-old-password">当前密码</label><input id="profile-old-password" type="password" name="oldPassword" required /></div>
          <div><label for="profile-new-password">新密码</label><input id="profile-new-password" type="password" name="newPassword" required /></div>
        </div>
        <div class="form-actions"><button type="submit" class="secondary" phx-disable-with="更新中…">更新密码</button></div>
      </form>
    </div>
    """
  end
end
