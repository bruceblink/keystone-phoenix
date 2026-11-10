defmodule KeystonePhoenixWeb.Live.AdminPages.Organization do
  @moduledoc "LiveView panels for departments, posts, roles, and menus."

  use Phoenix.Component

  def departments(assigns) do
    assigns = assign_new(assigns, :read_only, fn -> false end)

    ~H"""
    <div class="panel">
      <div class="form-actions">
        <button :if={!@read_only} type="button" class="refresh" phx-click="new-dept" phx-disable-with="处理中…">新建部门</button>
        <button type="button" class="refresh secondary" phx-click="refresh-depts" phx-disable-with="刷新中…">刷新部门</button>
      </div>
      <%= if @dept_feedback do %><p class="feedback" role="status"><%= @dept_feedback %></p><% end %>
      <p :if={@dept_rows == []} class="table-empty" role="status">暂无部门数据</p>
      <form :if={!@read_only} phx-submit="save-dept">
        <input type="hidden" name="deptId" value={@dept_form["deptId"]} />
        <div class="form-grid">
          <div><label for="dept-name">部门名称</label><input id="dept-name" name="deptName" value={@dept_form["deptName"]} required /></div>
          <div><label for="dept-parent">上级部门</label><select id="dept-parent" name="parentId"><option value="0">顶级部门</option><%= for parent <- @dept_rows do %><option value={parent["deptId"]} selected={to_string(@dept_form["parentId"]) == to_string(parent["deptId"])}><%= parent["deptName"] %></option><% end %></select></div>
          <div><label for="dept-order">排序</label><input id="dept-order" type="number" name="orderNum" value={@dept_form["orderNum"]} /></div>
          <div><label for="dept-leader">负责人</label><input id="dept-leader" name="leaderName" value={@dept_form["leaderName"] || ""} /></div>
          <div><label for="dept-phone">电话</label><input id="dept-phone" name="phone" value={@dept_form["phone"] || ""} /></div>
          <div><label for="dept-email">邮箱</label><input id="dept-email" name="email" value={@dept_form["email"] || ""} /></div>
          <div><label for="dept-status">状态</label><select id="dept-status" name="status"><option value="1" selected={@dept_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@dept_form["status"] in [0, "0"]}>停用</option></select></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存部门</button><button :if={@dept_form["deptId"] != ""} type="button" class="secondary" phx-click="new-dept" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
      <div class="table-scroll" role="region" tabindex="0" aria-label="数据表格"><table><caption class="sr-only">数据列表</caption><thead><tr><th>部门名称</th><th>负责人</th><th>电话</th><th>邮箱</th><th>状态</th><th>排序</th><th>操作</th></tr></thead><tbody>
        <%= for dept <- @dept_rows do %>
          <tr>
            <td><%= String.duplicate("　", dept["depth"] || 0) %><%= dept["deptName"] %></td><td><%= dept["leaderName"] || "" %></td><td><%= dept["phone"] || "" %></td><td><%= dept["email"] || "" %></td><td><%= if dept["status"] == 1, do: "正常", else: "停用" %></td><td><%= dept["orderNum"] %></td>
            <td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="edit-dept" phx-value-dept-id={dept["deptId"]} phx-disable-with="加载中…">编辑</button><button type="button" class="refresh" phx-click="toggle-dept-status" phx-value-dept-id={dept["deptId"]} phx-value-status={if dept["status"] == 1, do: 0, else: 1} phx-disable-with="处理中…"><%= if dept["status"] == 1, do: "停用", else: "启用" %></button><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-dept" phx-value-dept-id={dept["deptId"]} phx-disable-with="删除中…">删除</button></td>
          </tr>
        <% end %>
      </tbody></table></div>
    </div>
    """
  end

  def posts(assigns) do
    assigns = assign_new(assigns, :read_only, fn -> false end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button :if={!@read_only} type="button" class="refresh" phx-click="new-post" phx-disable-with="处理中…">新建岗位</button><button type="button" class="refresh secondary" phx-click="refresh-posts" phx-disable-with="刷新中…">刷新岗位</button></div>
      <%= if @post_feedback do %><p class="feedback" role="status"><%= @post_feedback %></p><% end %>
      <p :if={@post_rows == []} class="table-empty" role="status">暂无岗位数据</p>
      <form :if={!@read_only} phx-submit="save-post">
        <input type="hidden" name="postId" value={@post_form["postId"]} />
        <div class="form-grid">
          <div><label for="post-code">岗位编码</label><input id="post-code" name="postCode" value={@post_form["postCode"]} required /></div><div><label for="post-name">岗位名称</label><input id="post-name" name="postName" value={@post_form["postName"]} required /></div><div><label for="post-sort">排序</label><input id="post-sort" type="number" name="postSort" value={@post_form["postSort"]} /></div><div><label for="post-status">状态</label><select id="post-status" name="status"><option value="1" selected={@post_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@post_form["status"] in [0, "0"]}>停用</option></select></div><div class="wide"><label for="post-remark">备注</label><textarea id="post-remark" name="remark"><%= @post_form["remark"] || "" %></textarea></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存岗位</button><button :if={@post_form["postId"] != ""} type="button" class="secondary" phx-click="new-post" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
      <div class="table-scroll" role="region" tabindex="0" aria-label="数据表格"><table><caption class="sr-only">数据列表</caption><thead><tr><th>编码</th><th>名称</th><th>排序</th><th>状态</th><th>备注</th><th>操作</th></tr></thead><tbody><%= for post <- @post_rows do %><tr><td><%= post["postCode"] %></td><td><%= post["postName"] %></td><td><%= post["postSort"] %></td><td><%= if post["status"] == 1, do: "正常", else: "停用" %></td><td><%= post["remark"] || "" %></td><td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="edit-post" phx-value-post-id={post["postId"]} phx-disable-with="加载中…">编辑</button><button type="button" class="refresh" phx-click="toggle-post-status" phx-value-post-id={post["postId"]} phx-value-status={if post["status"] == 1, do: 0, else: 1} phx-disable-with="处理中…"><%= if post["status"] == 1, do: "停用", else: "启用" %></button><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-post" phx-value-post-id={post["postId"]} phx-disable-with="删除中…">删除</button></td></tr><% end %></tbody></table></div>
    </div>
    """
  end

  def roles(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:selected_role_id, fn -> "" end)
      |> assign_new(:selected_role_name, fn -> "" end)
      |> assign_new(:allocated_role_user_rows, fn -> [] end)
      |> assign_new(:unallocated_role_user_rows, fn -> [] end)
      |> assign_new(:role_user_feedback, fn -> nil end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button :if={!@read_only} type="button" class="refresh" phx-click="new-role" phx-disable-with="处理中…">新建角色</button><button type="button" class="refresh secondary" phx-click="refresh-roles" phx-disable-with="刷新中…">刷新角色</button></div>
      <%= if @role_feedback do %><p class="feedback" role="status"><%= @role_feedback %></p><% end %>
      <p :if={@role_rows == []} class="table-empty" role="status">暂无角色数据</p>
      <form :if={!@read_only} phx-submit="save-role">
        <input type="hidden" name="roleId" value={@role_form["roleId"]} />
        <div class="form-grid">
          <div><label for="role-name">角色名称</label><input id="role-name" name="roleName" value={@role_form["roleName"]} required /></div><div><label for="role-key">角色标识</label><input id="role-key" name="roleKey" value={@role_form["roleKey"]} required /></div><div><label for="role-sort">排序</label><input id="role-sort" type="number" name="roleSort" value={@role_form["roleSort"]} /></div><div><label for="role-scope">数据范围</label><select id="role-scope" name="dataScope"><%= for {value, label} <- [{1, "全部数据"}, {2, "自定义数据"}, {3, "本部门数据"}, {4, "本部门及以下"}, {5, "仅本人数据"}] do %><option value={value} selected={@role_form["dataScope"] in [value, to_string(value)]}><%= label %></option><% end %></select></div><div><label for="role-status">状态</label><select id="role-status" name="status"><option value="1" selected={@role_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@role_form["status"] in [0, "0"]}>停用</option></select></div><div><label for="role-depts">自定义部门 ID</label><input id="role-depts" name="deptIdSet" value={@role_form["deptIdSet"] || ""} /></div><div class="wide"><label for="role-menus">授权菜单 ID（逗号分隔）</label><input id="role-menus" name="menuIds" value={@role_form["menuIds"] || ""} /></div><div class="wide"><label for="role-remark">备注</label><textarea id="role-remark" name="remark"><%= @role_form["remark"] || "" %></textarea></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存角色</button><button :if={@role_form["roleId"] != ""} type="button" class="secondary" phx-click="new-role" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
      <div class="table-scroll" role="region" tabindex="0" aria-label="数据表格"><table><caption class="sr-only">数据列表</caption><thead><tr><th>角色名称</th><th>角色标识</th><th>数据范围</th><th>用户数</th><th>状态</th><th>排序</th><th>操作</th></tr></thead><tbody><%= for role <- @role_rows do %><tr><td><%= role["roleName"] %></td><td><%= role["roleKey"] %></td><td><%= role["dataScopeStr"] %></td><td><%= role["userCount"] %></td><td><%= role["statusStr"] %></td><td><%= role["roleSort"] %></td><td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="select-role" phx-value-role-id={role["roleId"]} phx-disable-with="加载中…">管理用户</button><button type="button" class="refresh" phx-click="edit-role" phx-value-role-id={role["roleId"]} phx-disable-with="加载中…">编辑</button><button type="button" class="refresh" phx-click="toggle-role-status" phx-value-role-id={role["roleId"]} phx-value-status={if role["status"] == 1, do: 0, else: 1} phx-disable-with="处理中…"><%= if role["status"] == 1, do: "停用", else: "启用" %></button><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-role" phx-value-role-id={role["roleId"]} phx-disable-with="删除中…">删除</button></td></tr><% end %></tbody></table></div>
      <%= if @selected_role_id != "" do %>
        <section id="role-user-management">
          <h3>角色用户：<%= @selected_role_name %></h3>
          <%= if @role_user_feedback do %><p class="feedback" role="status"><%= @role_user_feedback %></p><% end %>
          <div class="monitor-grid details">
            <div><h3>已分配用户（<%= length(@allocated_role_user_rows) %>）</h3><div class="table-scroll" role="region" tabindex="0" aria-label="数据表格"><table><caption class="sr-only">数据列表</caption><thead><tr><th>用户名</th><th>昵称</th><th>操作</th></tr></thead><tbody><%= for user <- @allocated_role_user_rows do %><tr><td><%= user["username"] %></td><td><%= user["nickname"] %></td><td><button :if={!@read_only} type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="unassign-role-user" phx-value-user-id={user["userId"]} phx-disable-with="处理中…">取消分配</button></td></tr><% end %></tbody></table></div></div>
            <div><h3>可分配用户（<%= length(@unallocated_role_user_rows) %>）</h3><div class="table-scroll" role="region" tabindex="0" aria-label="数据表格"><table><caption class="sr-only">数据列表</caption><thead><tr><th>用户名</th><th>昵称</th><th>操作</th></tr></thead><tbody><%= for user <- @unallocated_role_user_rows do %><tr><td><%= user["username"] %></td><td><%= user["nickname"] %></td><td><button :if={!@read_only} type="button" class="refresh" phx-click="assign-role-user" phx-value-user-id={user["userId"]} phx-disable-with="处理中…">分配</button></td></tr><% end %></tbody></table></div></div>
          </div>
        </section>
      <% end %>
    </div>
    """
  end

  def menus(assigns) do
    assigns = assign_new(assigns, :read_only, fn -> false end)

    ~H"""
    <div class="panel">
      <div class="form-actions"><button :if={!@read_only} type="button" class="refresh" phx-click="new-menu" phx-disable-with="处理中…">新建菜单</button><button type="button" class="refresh secondary" phx-click="refresh-menus" phx-disable-with="刷新中…">刷新菜单</button></div>
      <%= if @menu_feedback do %><p class="feedback" role="status"><%= @menu_feedback %></p><% end %>
      <p :if={@menu_rows == []} class="table-empty" role="status">暂无菜单数据</p>
      <form :if={!@read_only} phx-submit="save-menu">
        <input type="hidden" name="menuId" value={@menu_form["menuId"]} />
        <div class="form-grid">
          <div><label for="menu-name">菜单名称</label><input id="menu-name" name="menuName" value={@menu_form["menuName"]} required /></div><div><label for="menu-parent">上级菜单</label><select id="menu-parent" name="parentId"><option value="0">顶级菜单</option><%= for parent <- @menu_rows do %><option value={parent["menuId"]} selected={to_string(@menu_form["parentId"]) == to_string(parent["menuId"])}><%= String.duplicate("　", parent["depth"] || 0) %><%= parent["menuName"] %></option><% end %></select></div><div><label for="menu-type">菜单类型</label><select id="menu-type" name="menuType"><option value="0" selected={@menu_form["menuType"] in [0, "0"]}>权限</option><option value="1" selected={@menu_form["menuType"] in [1, "1"]}>菜单</option><option value="2" selected={@menu_form["menuType"] in [2, "2"]}>目录</option></select></div><div><label for="menu-router">路由名称</label><input id="menu-router" name="routerName" value={@menu_form["routerName"] || ""} /></div><div><label for="menu-path">路径</label><input id="menu-path" name="path" value={@menu_form["path"] || ""} /></div><div><label for="menu-permission">权限标识</label><input id="menu-permission" name="permission" value={@menu_form["permission"] || ""} /></div><div><label for="menu-button">按钮权限</label><select id="menu-button" name="isButton"><option value="false" selected={@menu_form["isButton"] in [false, "false", 0, "0"]}>否</option><option value="true" selected={@menu_form["isButton"] in [true, "true", 1, "1"]}>是</option></select></div><div><label for="menu-status">状态</label><select id="menu-status" name="status"><option value="1" selected={@menu_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@menu_form["status"] in [0, "0"]}>停用</option></select></div><div class="wide"><label for="menu-meta">元数据 JSON</label><textarea id="menu-meta" name="metaInfo"><%= @menu_form["metaInfo"] || "{}" %></textarea></div><div class="wide"><label for="menu-remark">备注</label><textarea id="menu-remark" name="remark"><%= @menu_form["remark"] || "" %></textarea></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存菜单</button><button :if={@menu_form["menuId"] != ""} type="button" class="secondary" phx-click="new-menu" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
      <div class="table-scroll" role="region" tabindex="0" aria-label="数据表格"><table><caption class="sr-only">数据列表</caption><thead><tr><th>菜单名称</th><th>类型</th><th>路径</th><th>权限标识</th><th>状态</th><th>操作</th></tr></thead><tbody><%= for menu <- @menu_rows do %><tr><td><%= String.duplicate("　", menu["depth"] || 0) %><%= menu["menuName"] %></td><td><%= menu["menuTypeStr"] %></td><td><%= menu["path"] || "" %></td><td><%= menu["permission"] || "" %></td><td><%= menu["statusStr"] %></td><td :if={!@read_only} class="table-actions"><button type="button" class="refresh" phx-click="edit-menu" phx-value-menu-id={menu["menuId"]} phx-disable-with="加载中…">编辑</button><button type="button" class="refresh" phx-click="toggle-menu-status" phx-value-menu-id={menu["menuId"]} phx-value-status={if menu["status"] == 1, do: 0, else: 1} phx-disable-with="处理中…"><%= if menu["status"] == 1, do: "停用", else: "启用" %></button><button type="button" class="refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="delete-menu" phx-value-menu-id={menu["menuId"]} phx-disable-with="删除中…">删除</button></td></tr><% end %></tbody></table></div>
    </div>
    """
  end
end
