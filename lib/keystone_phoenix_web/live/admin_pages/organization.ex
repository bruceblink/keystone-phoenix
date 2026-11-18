defmodule KeystonePhoenixWeb.Live.AdminPages.Organization do
  @moduledoc "LiveView panels for departments, posts, roles, and menus."

  use Phoenix.Component

  import KeystonePhoenixWeb.Live.AdminPages.Pagination
  import KeystonePhoenixWeb.Live.AdminPages.Modal
  import KeystonePhoenixWeb.Live.AdminPages.ListToolbar
  import KeystonePhoenixWeb.Live.AdminPages.Navigation, only: [nav_icon: 1]
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminPages.OrganizationData
  alias KeystonePhoenixWeb.Live.AdminPages.OrganizationFilters
  alias KeystonePhoenixWeb.Live.AdminPages.Status
  alias KeystonePhoenix.Authz.PermissionCatalog

  def departments(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:active_modal, fn -> nil end)
      |> assign_new(:dept_filter, fn -> %{"keyword" => "", "status" => "all"} end)

    ~H"""
    <div class="departments-page">
      <div class="page-heading">
        <div>
          <p class="eyebrow">ORGANIZATION / STRUCTURE</p>
          <h1>组织结构</h1>
          <p class="page-description">按层级查看部门、负责人和启用状态。新增和编辑在模态框中完成。</p>
        </div>
      </div>
      <%= if @dept_feedback do %><p id="dept-feedback" class={Feedback.class(@dept_feedback)} role={Feedback.role(@dept_feedback)} aria-live={Feedback.live(@dept_feedback)}><%= Feedback.message(@dept_feedback) %></p><% end %>
      <section class="card departments-filter-card">
        <form class="departments-filter-form" phx-submit="refresh-depts">
          <label><span>组织名称或编码</span><input id="dept-filter-keyword" name="deptKeyword" value={@dept_filter["keyword"]} placeholder="按组织名称或编码筛选" autocomplete="off" /></label>
          <input type="hidden" name="deptStatus" value={@dept_filter["status"] || "all"} />
          <div class="departments-filter-actions"><button type="submit" class="button button-primary button-sm"><.nav_icon name="search" />查询</button><button type="button" class="button button-ghost button-sm" phx-click="refresh-depts" phx-value-reset="true">重置</button></div>
        </form>
      </section>
      <%= if @active_modal == "dept" do %>
        <.modal id="dept-modal" title={if @dept_form["deptId"] == "", do: "新建部门", else: "编辑部门"} description="维护组织层级和负责人信息。">
    <form :if={!@read_only} aria-describedby="dept-feedback" phx-submit="save-dept">
        <input type="hidden" name="deptId" value={@dept_form["deptId"]} />
        <div class="form-grid">
          <div><label for="dept-name">部门名称</label><input id="dept-name" name="deptName" value={@dept_form["deptName"]} required /></div>
          <div><label for="dept-parent">上级部门</label><select id="dept-parent" name="parentId"><option value="">顶级部门</option><%= for parent <- @dept_rows do %><option value={parent["deptId"]} selected={to_string(@dept_form["parentId"]) == to_string(parent["deptId"])}><%= parent["deptName"] %></option><% end %></select></div>
          <div><label for="dept-order">排序</label><input id="dept-order" type="number" name="orderNum" value={@dept_form["orderNum"]} /></div>
          <div><label for="dept-leader">负责人</label><input id="dept-leader" name="leaderName" value={@dept_form["leaderName"] || ""} /></div>
          <div><label for="dept-phone">电话</label><input id="dept-phone" name="phone" value={@dept_form["phone"] || ""} /></div>
          <div><label for="dept-email">邮箱</label><input id="dept-email" name="email" value={@dept_form["email"] || ""} /></div>
          <div><label for="dept-status">状态</label><select id="dept-status" name="status"><option value="1" selected={@dept_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@dept_form["status"] in [0, "0"]}>停用</option></select></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存部门</button><button :if={@dept_form["deptId"] != ""} type="button" class="secondary" phx-click="close-modal" phx-value-modal="dept" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
        </.modal>
      <% end %>
      <section class="card table-card departments-table-card" aria-labelledby="departments-table-title">
        <.list_toolbar label="组织结构列表操作">
          <button :if={!@read_only} type="button" class="button button-primary button-sm" phx-click="new-dept" phx-disable-with="处理中…"><.nav_icon name="plus" />新增组织</button>
          <button type="button" class="button button-secondary button-sm" phx-click="refresh-depts" phx-disable-with="刷新中…"><.nav_icon name="refresh" />刷新结构</button>
        </.list_toolbar>
        <div class="card-header">
          <div>
            <h2 id="departments-table-title">组织结构</h2>
            <p>当前匹配 <%= length(OrganizationFilters.filtered_depts(@dept_rows, @dept_filter)) %> 个组织节点。</p>
          </div>
          <span class="badge badge-info">系统 API</span>
        </div>
        <%= if OrganizationFilters.filtered_depts(@dept_rows, @dept_filter) == [] do %>
          <div class="departments-empty" role="status"><strong>没有匹配的组织</strong><p>调整筛选条件后重试，或清空筛选条件查看完整组织结构。</p></div>
        <% else %>
        <div class="departments-table-wrap"><table class="departments-table"><caption class="sr-only">组织结构</caption><thead><tr><th scope="col">组织名称</th><th scope="col">组织编码</th><th scope="col">排序</th><th scope="col">状态</th><th scope="col">操作</th></tr></thead><tbody>
            <%= for dept <- OrganizationFilters.filtered_depts(@dept_rows, @dept_filter) do %>
              <tr>
                <td><div class="department-cell"><span class="department-marker" aria-hidden="true"><.nav_icon name="building" /></span><strong><%= String.duplicate("　", dept["depth"] || 0) %><%= dept["deptName"] %></strong></div></td><td class="department-code"><%= dept["deptCode"] || dept["deptId"] %></td><td><%= dept["orderNum"] %></td><td><span class={"status-badge #{Status.normal_paused(dept["status"])}"}><%= if dept["status"] == 1, do: "启用", else: "停用" %></span></td>
                <td :if={!@read_only} class="table-actions"><button type="button" class="button button-ghost button-sm" phx-click="edit-dept" phx-value-dept-id={dept["deptId"]} phx-disable-with="加载中…">编辑</button><button type="button" class="button button-ghost button-sm" phx-confirm="确认删除此组织吗？" phx-click="delete-dept" phx-value-dept-id={dept["deptId"]} phx-disable-with="删除中…">删除</button></td>
              </tr>
            <% end %>
          </tbody></table></div>
        <% end %>
      </section>
    </div>
    """
  end

  def posts(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:active_modal, fn -> nil end)
      |> assign_new(:page_num, fn -> 1 end)
      |> assign_new(:page_size, fn -> 20 end)
      |> assign_new(:post_total, fn -> length(Map.get(assigns, :post_rows, [])) end)
      |> assign_new(:post_filter, fn -> %{"keyword" => "", "status" => "all"} end)
      |> assign_new(:permissions, fn -> [] end)

    ~H"""
    <div class="posts-page">
      <div class="page-heading">
        <div>
          <p class="eyebrow">ORGANIZATION / POSTS</p>
          <h1>岗位管理</h1>
          <p class="page-description">查询岗位编码、显示排序和启用状态。新增和编辑在模态框中完成。</p>
        </div>
      </div>
      <%= if @post_feedback do %><p id="post-feedback" class={Feedback.class(@post_feedback)} role={Feedback.role(@post_feedback)} aria-live={Feedback.live(@post_feedback)}><%= Feedback.message(@post_feedback) %></p><% end %>
      <section class="card posts-filter-card">
        <form class="posts-filter-form" phx-submit="refresh-posts">
          <label><span>岗位名称或编码</span><input id="post-filter-keyword" name="postKeyword" value={@post_filter["keyword"]} placeholder="按岗位名称或编码筛选" autocomplete="off" /></label>
          <label><span>岗位状态</span><select id="post-filter-status" name="postStatus"><option value="all" selected={@post_filter["status"] in [nil, "all"]}>全部状态</option><option value="1" selected={@post_filter["status"] == "1"}>启用</option><option value="0" selected={@post_filter["status"] == "0"}>停用</option></select></label>
          <div class="posts-filter-actions"><button type="submit" class="button button-primary button-sm"><.nav_icon name="search" />查询</button><button type="button" class="button button-ghost button-sm" phx-click="refresh-posts" phx-value-reset="true">重置</button></div>
        </form>
      </section>
      <%= if @active_modal == "post" do %>
        <.modal id="post-modal" title={if @post_form["postId"] == "", do: "新建岗位", else: "编辑岗位"} description="维护岗位编码、排序和状态。">
    <form :if={!@read_only} aria-describedby="post-feedback" phx-submit="save-post">
        <input type="hidden" name="postId" value={@post_form["postId"]} />
        <div class="form-grid">
          <div><label for="post-code">岗位编码</label><input id="post-code" name="postCode" value={@post_form["postCode"]} required /></div><div><label for="post-name">岗位名称</label><input id="post-name" name="postName" value={@post_form["postName"]} required /></div><div><label for="post-sort">排序</label><input id="post-sort" type="number" name="postSort" value={@post_form["postSort"]} /></div><div><label for="post-status">状态</label><select id="post-status" name="status"><option value="1" selected={@post_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@post_form["status"] in [0, "0"]}>停用</option></select></div><div class="wide"><label for="post-remark">备注</label><textarea id="post-remark" name="remark"><%= @post_form["remark"] || "" %></textarea></div>
        </div>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存岗位</button><button :if={@post_form["postId"] != ""} type="button" class="secondary" phx-click="close-modal" phx-value-modal="post" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
        </.modal>
      <% end %>
      <section class="card table-card posts-table-card" aria-labelledby="posts-table-title">
        <.list_toolbar label="岗位列表操作">
          <button :if={!@read_only} type="button" class="button button-primary button-sm" phx-click="new-post" phx-disable-with="处理中…"><.nav_icon name="plus" />新增岗位</button>
          <button :if={"post:export" in @permissions} type="button" class="button button-secondary button-sm" phx-click="export-posts" phx-disable-with="导出中…"><.nav_icon name="download" />导出 Excel</button>
          <button type="button" class="button button-secondary button-sm" phx-click="refresh-posts" phx-disable-with="刷新中…"><.nav_icon name="refresh" />刷新岗位</button>
        </.list_toolbar>
        <div class="card-header">
          <div>
            <h2 id="posts-table-title">岗位列表</h2>
            <p>当前匹配 <%= @post_total %> 个岗位。</p>
          </div>
          <span class="badge badge-info">系统 API</span>
        </div>
        <%= if @post_rows == [] do %>
          <div class="posts-empty" role="status"><span class="posts-empty-icon" aria-hidden="true"><.nav_icon name="briefcase" /></span><strong>没有匹配的岗位</strong><p>调整筛选条件后重试，或清空筛选条件查看全部岗位。</p></div>
        <% else %>
        <div class="posts-table-wrap"><table class="posts-table"><caption class="sr-only">岗位列表</caption><thead><tr><th scope="col">岗位</th><th scope="col">编码</th><th scope="col">排序</th><th scope="col">状态</th><th scope="col">操作</th></tr></thead><tbody><%= for post <- @post_rows do %><tr><td><div class="post-cell"><span class="post-cell-icon" aria-hidden="true"><.nav_icon name="briefcase" /></span><div><strong><%= post["postName"] %></strong><small><%= post["postCode"] %></small></div></div></td><td class="post-code"><%= post["postCode"] %></td><td><%= post["postSort"] %></td><td><span class={"status-badge #{Status.normal_paused(post["status"])}"}><%= if post["status"] == 1, do: "启用", else: "停用" %></span></td><td :if={!@read_only} class="table-actions"><button type="button" class="button button-ghost button-sm" phx-click="edit-post" phx-value-post-id={post["postId"]} phx-disable-with="加载中…">编辑</button><button type="button" class="button button-ghost button-sm" phx-click="delete-post" phx-value-post-id={post["postId"]} phx-confirm="确认删除此岗位吗？" phx-disable-with="删除中…">删除</button></td></tr><% end %></tbody></table></div>
        <.pagination panel="posts" page_num={min(@page_num, page_count(@post_total, @page_size))} page_size={@page_size} total={@post_total} />
        <% end %>
      </section>
      <span id="post-download-hook" phx-hook="DownloadFile" hidden></span>
    </div>
    """
  end

  def roles(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:active_modal, fn -> nil end)
      |> assign_new(:selected_role_ids, fn -> [] end)
      |> assign_new(:selected_role_id, fn -> "" end)
      |> assign_new(:selected_role_name, fn -> "" end)
      |> assign_new(:role_filter, fn -> %{"keyword" => "", "status" => "all"} end)
      |> assign_new(:role_page_rows, fn -> assigns[:role_rows] || [] end)
      |> assign_new(:role_total, fn ->
        length(assigns[:role_page_rows] || assigns[:role_rows] || [])
      end)
      |> assign_new(:page_num, fn -> 1 end)
      |> assign_new(:page_size, fn -> 20 end)
      |> assign_new(:permissions, fn -> [] end)
      |> assign_new(:menu_rows, fn -> [] end)
      |> assign_new(:allocated_role_user_rows, fn -> [] end)
      |> assign_new(:unallocated_role_user_rows, fn -> [] end)
      |> assign_new(:role_user_feedback, fn -> nil end)
      |> assign_new(:allocated_page_num, fn -> 1 end)
      |> assign_new(:unallocated_page_num, fn -> 1 end)
      |> assign_new(:role_user_page_size, fn -> 50 end)
      |> assign_new(:role_permission_query, fn -> "" end)
      |> assign_new(:role_permissions_feedback, fn -> nil end)
      |> assign_new(:role_permissions_form, fn ->
        %{"roleId" => "", "roleName" => "", "permissions" => "", "loaded" => false}
      end)

    ~H"""
    <div class="roles-page">
      <div class="page-heading">
        <div>
          <p class="eyebrow">ACCESS / ROLES</p>
          <h1>角色管理</h1>
          <p class="page-description">查询角色状态、数据范围和用户数量。新增和编辑在模态框中完成。</p>
        </div>
      </div>
      <%= if @role_feedback && @active_modal != "role-delete" do %><p id="role-feedback" class={Feedback.class(@role_feedback)} role={Feedback.role(@role_feedback)} aria-live={Feedback.live(@role_feedback)}><%= Feedback.message(@role_feedback) %></p><% end %>
      <section class="card roles-filter-card">
        <form class="roles-filter-form" phx-submit="refresh-roles">
          <label><span>角色名称或标识</span><input id="role-filter-keyword" name="roleKeyword" value={@role_filter["keyword"]} placeholder="按角色名称或编码筛选" autocomplete="off" /></label>
          <label><span>角色状态</span><select id="role-filter-status" name="roleStatus"><option value="all" selected={@role_filter["status"] in [nil, "all"]}>全部状态</option><option value="enabled" selected={@role_filter["status"] in ["enabled", "1"]}>启用</option><option value="disabled" selected={@role_filter["status"] in ["disabled", "0"]}>停用</option></select></label>
          <div class="roles-filter-actions"><button type="submit" class="button button-primary button-sm"><.nav_icon name="search" />查询</button><button type="button" class="button button-ghost button-sm" phx-click="refresh-roles" phx-value-reset="true">重置</button></div>
        </form>
      </section>
      <.modal :if={@active_modal == "role-delete"} id="role-delete-modal" title="删除角色" description="请确认本次批量操作的范围。" size="sm">
        <div class="delete-confirm-panel"><span class="delete-confirm-icon" aria-hidden="true">!</span><div><strong>将删除 <%= length(@selected_role_ids) %> 条角色记录</strong><p>删除后不可恢复。请确认已选择正确的记录。</p></div></div>
        <p :if={@role_feedback} class={Feedback.class(@role_feedback)} role={Feedback.role(@role_feedback)} aria-live={Feedback.live(@role_feedback)}><%= Feedback.message(@role_feedback) %><small :if={Feedback.code(@role_feedback)} id="role-delete-error-code">错误码：<%= Feedback.code(@role_feedback) %></small></p>
        <:footer><button type="button" class="button button-ghost" phx-click="close-modal">取消</button><button type="submit" form="role-delete-form" class="button button-danger" phx-disable-with="删除中…">确认删除 <%= length(@selected_role_ids) %> 条</button></:footer>
      </.modal>
      <%= if @active_modal == "role" do %>
        <.modal id="role-modal" title={if @role_form["roleId"] == "", do: "新建角色", else: "编辑角色"} description="维护角色权限和数据范围。">
          <form :if={role_form_allowed?(@role_form, @permissions)} aria-describedby="role-feedback" phx-submit="save-role">
            <input type="hidden" name="roleId" value={@role_form["roleId"]} />
            <div class="form-grid">
              <div><label for="role-name">角色名称</label><input id="role-name" name="roleName" value={@role_form["roleName"]} required /></div>
              <div><label for="role-key">角色标识</label><input id="role-key" name="roleKey" value={@role_form["roleKey"]} required /></div>
              <div><label for="role-sort">排序</label><input id="role-sort" type="number" name="roleSort" value={@role_form["roleSort"]} /></div>
              <div><label for="role-status">状态</label><select id="role-status" name="status"><option value="1" selected={@role_form["status"] in [1, "1"]}>正常</option><option value="0" selected={@role_form["status"] in [0, "0"]}>停用</option></select></div>
              <%= if "role:manage" in @permissions do %>
                <div><label for="role-scope">数据范围</label><select id="role-scope" name="dataScope"><%= for {value, label} <- [{"ALL", "全部数据"}, {"TENANT", "当前租户数据"}, {"CUSTOM", "自定义数据"}, {"DEPARTMENT", "本部门数据"}, {"DEPARTMENT_AND_CHILDREN", "本部门及以下"}, {"SELF", "仅本人数据"}, {"OWNER", "本人拥有"}, {"MEMBER", "成员关系"}] do %><option value={value} selected={@role_form["dataScope"] in [value, to_string(value)]}><%= label %></option><% end %></select></div>
                <div><label for="role-depts">自定义部门 ID</label><input id="role-depts" name="deptIdSet" value={@role_form["deptIdSet"] || ""} /></div>
                <div class="wide"><label for="role-permission-query">权限标识</label><input id="role-permission-query" name="permissionQuery" value={@role_permission_query} placeholder="搜索权限，例如 user:read" phx-change="filter-role-permissions" phx-debounce="200" autocomplete="off" /><input type="hidden" id="role-permissions" name="permissions" value={@role_form["permissions"] || ""} /><.role_permission_picker permissions={@permissions} selected={@role_form["permissions"]} query={@role_permission_query} /></div>
                <div class="wide"><label for="role-menu-ids">菜单权限</label><select id="role-menu-ids" name="menuIds[]" multiple size="8"><%= for menu <- @menu_rows do %><% menu_id = menu["menuId"] || menu["id"] %><option value={menu_id} selected={to_string(menu_id) in String.split(to_string(@role_form["menuIds"] || ""), ",", trim: true)}><%= String.duplicate("　", menu["depth"] || 0) %><%= menu["name"] || menu["menuName"] %>（<%= menu["permission"] || menu["code"] || menu["menuCode"] || "无标识" %>）</option><% end %></select><small>按住 Ctrl 或 Command 可选择多个菜单。保存后会同步角色菜单绑定。</small></div>
              <% else %>
                <div class="wide"><p id="role-metadata-preserved" class="form-help" role="status">当前账号没有 role:manage 权限。本次只保存角色基础资料，现有数据范围、菜单和权限绑定都会保留。</p><p>数据范围：<strong><%= @role_form["dataScope"] || "—" %></strong>；自定义部门：<strong><%= @role_form["deptIdSet"] || "—" %></strong></p></div>
              <% end %>
              <div class="wide"><label for="role-remark">备注</label><textarea id="role-remark" name="remark"><%= @role_form["remark"] || "" %></textarea></div>
            </div>
            <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存角色</button><button :if={@role_form["roleId"] != ""} type="button" class="secondary" phx-click="close-modal" phx-value-modal="role" phx-disable-with="处理中…">取消编辑</button></div>
          </form>
        </.modal>
      <% end %>
      <.modal :if={@active_modal == "role-permissions"} id="role-permissions-modal" title={"配置角色权限：#{@role_permissions_form["roleName"]}"} description="独立维护权限绑定，不修改角色基础资料、数据范围或菜单绑定。">
        <%= if @role_permissions_feedback do %><p id="role-permissions-feedback" class={Feedback.class(@role_permissions_feedback)} role={Feedback.role(@role_permissions_feedback)} aria-live={Feedback.live(@role_permissions_feedback)}><%= Feedback.message(@role_permissions_feedback) %><small :if={Feedback.code(@role_permissions_feedback)}>错误码：<%= Feedback.code(@role_permissions_feedback) %></small></p><% end %>
        <%= if @role_permissions_form["loaded"] do %>
          <form phx-submit="save-role-permissions">
            <input type="hidden" name="roleId" value={@role_permissions_form["roleId"]} />
            <input type="hidden" id="managed-role-permissions" name="permissions" value={@role_permissions_form["permissions"]} />
            <label for="managed-role-permission-query">权限标识</label><input id="managed-role-permission-query" name="permissionQuery" value={@role_permission_query} placeholder="搜索权限，例如 user:read" phx-change="filter-role-permissions" phx-debounce="200" autocomplete="off" />
            <.role_permission_picker permissions={@permissions} selected={@role_permissions_form["permissions"]} query={@role_permission_query} />
            <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存权限</button><button type="button" class="secondary" phx-click="close-modal" phx-value-modal="role-permissions">取消</button></div>
          </form>
        <% else %>
          <p role="status">角色权限读取失败。请关闭窗口后刷新角色列表，再重试。</p>
          <div class="form-actions"><button type="button" class="secondary" phx-click="close-modal" phx-value-modal="role-permissions">关闭</button></div>
        <% end %>
      </.modal>
      <section class="card table-card roles-table-card" aria-labelledby="roles-table-title">
        <.list_toolbar label="角色列表操作">
          <button :if={"role:create" in @permissions} type="button" class="button button-primary button-sm" phx-click="new-role" phx-disable-with="处理中…"><.nav_icon name="plus" />新增角色</button>
          <button :if={"role:export" in @permissions} type="button" class="button button-secondary button-sm" phx-click="export-roles" phx-disable-with="导出中…"><.nav_icon name="download" />导出 Excel</button>
          <button :if={"role:delete" in @permissions} type="button" id="role-delete-toolbar-action" class="button button-danger button-sm" phx-click="open-role-delete" disabled={@selected_role_ids == [] or @role_page_rows == []}>删除角色（<%= length(@selected_role_ids) %>）</button>
          <button type="button" class="button button-secondary button-sm" phx-click="refresh-roles" phx-disable-with="刷新中…"><.nav_icon name="refresh" />刷新列表</button>
        </.list_toolbar>
        <div class="card-header">
          <div>
            <h2 id="roles-table-title">角色列表</h2>
            <p>当前匹配 <%= @role_total %> 个角色。</p>
          </div>
          <span class="badge badge-info">系统 API</span>
        </div>
        <form id="role-delete-form" phx-submit="delete-role">
        <%= if @role_page_rows == [] do %>
          <div class="roles-empty" role="status"><strong>没有匹配的角色</strong><p>调整筛选条件后重试，或清空筛选条件查看全部角色。</p></div>
        <% else %>
        <% filtered_role_rows = OrganizationFilters.filtered_roles(@role_page_rows, @role_filter) %>
        <% all_roles_selected = filtered_role_rows != [] and Enum.all?(filtered_role_rows, &(to_string(&1["roleId"]) in @selected_role_ids)) %>
        <div class="roles-table-wrap"><table class="roles-table"><caption class="sr-only">角色列表</caption><thead><tr><th scope="col"><input :if={"role:delete" in @permissions} type="checkbox" aria-label="选择当前角色" checked={all_roles_selected} phx-click="toggle-all-role-selection" phx-value-selected={if all_roles_selected, do: "false", else: "true"} /></th><th scope="col">角色</th><th scope="col">数据范围</th><th scope="col">组织范围</th><th scope="col">权限数</th><th scope="col">状态</th><th scope="col">操作</th></tr></thead><tbody><%= for role <- filtered_role_rows do %><tr><td><input :if={"role:delete" in @permissions} type="checkbox" name="role-ids[]" value={role["roleId"]} aria-label={"选择角色 #{role["roleName"]}"} checked={to_string(role["roleId"]) in @selected_role_ids} phx-click="toggle-role-selection" phx-value-role-id={role["roleId"]} phx-value-selected={if to_string(role["roleId"]) in @selected_role_ids, do: "false", else: "true"} /></td><td><div class="role-cell"><span class="role-cell-icon" aria-hidden="true"><.nav_icon name="user-cog" /></span><div><strong><%= role["roleName"] %></strong><small><%= role["roleKey"] %></small></div></div></td><td><span class="badge badge-neutral"><%= role["dataScopeStr"] %></span></td><td><%= role["deptScope"] || "—" %></td><td><%= role["permissionCount"] || "—" %></td><td><span class={"status-badge #{Status.normal_paused(role["status"])}"}><%= if role["status"] == 1, do: "启用", else: "停用" %></span></td><td class="table-actions"><button type="button" class="button button-ghost button-sm" phx-click="select-role" phx-value-role-id={role["roleId"]} phx-disable-with="加载中…">成员</button><button :if={"role:update" in @permissions} type="button" class="button button-ghost button-sm" phx-click="edit-role" phx-value-role-id={role["roleId"]} phx-disable-with="加载中…">编辑</button><button :if={"role:manage" in @permissions} type="button" class="button button-ghost button-sm" phx-click="open-role-permissions" phx-value-role-id={role["roleId"]} phx-disable-with="加载中…">配置权限</button></td></tr><% end %></tbody></table></div>
        <.pagination panel="roles" page_num={min(@page_num, page_count(@role_total, @page_size))} page_size={@page_size} total={@role_total} />
        <% end %>
        </form>
      </section>
      <span id="role-download-hook" phx-hook="DownloadFile" hidden></span>
      <%= if @selected_role_id != "" do %>
        <section id="role-user-management" class="card role-user-management">
          <div class="card-header">
            <div>
              <h2>角色用户：<%= @selected_role_name %></h2>
              <p>管理当前角色的用户分配。</p>
            </div>
            <button type="button" class="button button-ghost button-sm" phx-click="close-role-users" phx-disable-with="关闭中…">关闭</button>
          </div>
          <%= if @role_user_feedback do %><p id="role-user-feedback" class={Feedback.class(@role_user_feedback)} role={Feedback.role(@role_user_feedback)} aria-live={Feedback.live(@role_user_feedback)}><%= Feedback.message(@role_user_feedback) %></p><% end %>
          <div class="monitor-grid details">
            <div><h3>已分配用户（<%= length(@allocated_role_user_rows) %>）</h3><div class="table-wrap"><div class="table-scroll" role="region" tabindex="0" aria-label="已分配用户列表"><table><caption class="sr-only">已分配用户列表</caption><thead><tr><th scope="col">用户名</th><th scope="col">昵称</th><th scope="col">操作</th></tr></thead><tbody><%= for user <- page_rows(@allocated_role_user_rows, @allocated_page_num, @role_user_page_size) do %><tr><td><%= user["username"] %></td><td><%= user["nickname"] %></td><td><button :if={"role:assign" in @permissions} type="button" class="button button-danger refresh danger-action" phx-confirm="确认执行此危险操作吗？" phx-click="unassign-role-user" phx-value-user-id={user["userId"]} phx-disable-with="处理中…">取消分配</button></td></tr><% end %></tbody></table></div></div><.pagination panel="role-users-allocated" page_num={min(@allocated_page_num, page_count(length(@allocated_role_user_rows), @role_user_page_size))} page_size={@role_user_page_size} total={length(@allocated_role_user_rows)} /></div>
            <div><h3>可分配用户（<%= length(@unallocated_role_user_rows) %>）</h3><div class="table-wrap"><div class="table-scroll" role="region" tabindex="0" aria-label="可分配用户列表"><table><caption class="sr-only">可分配用户列表</caption><thead><tr><th scope="col">用户名</th><th scope="col">昵称</th><th scope="col">操作</th></tr></thead><tbody><%= for user <- page_rows(@unallocated_role_user_rows, @unallocated_page_num, @role_user_page_size) do %><tr><td><%= user["username"] %></td><td><%= user["nickname"] %></td><td><button :if={"role:assign" in @permissions} type="button" class="button button-ghost refresh" phx-click="assign-role-user" phx-value-user-id={user["userId"]} phx-disable-with="处理中…">分配</button></td></tr><% end %></tbody></table></div></div><.pagination panel="role-users-unallocated" page_num={min(@unallocated_page_num, page_count(length(@unallocated_role_user_rows), @role_user_page_size))} page_size={@role_user_page_size} total={length(@unallocated_role_user_rows)} /></div>
          </div>
        </section>
      <% end %>
    </div>
    """
  end

  def menus(assigns) do
    assigns =
      assigns
      |> assign_new(:read_only, fn -> false end)
      |> assign_new(:active_modal, fn -> nil end)
      |> assign_new(:menu_filter, fn -> "" end)
      |> assign_new(:menu_role_codes, fn -> [] end)
      |> assign_new(:role_rows, fn -> [] end)
      |> assign_new(:permissions, fn -> [] end)

    ~H"""
    <div class="menus-page">
      <div class="page-heading">
        <div>
          <p class="eyebrow">ACCESS / MENUS</p>
          <h1>菜单与权限</h1>
          <p class="page-description">查询菜单层级、路由和权限标识。新增和编辑在模态框中完成，删除操作需要确认。</p>
        </div>
      </div>
      <%= if @menu_feedback && @active_modal != "menu" do %><p id="menu-feedback" class={Feedback.class(@menu_feedback)} role={Feedback.role(@menu_feedback)} aria-live={Feedback.live(@menu_feedback)}><%= Feedback.message(@menu_feedback) %><small :if={Feedback.code(@menu_feedback)}>错误码：<%= Feedback.code(@menu_feedback) %></small></p><% end %>
      <section class="card menus-filter-card">
        <form class="menus-filter-form" phx-submit="refresh-menus">
          <label><span>菜单名称、编码或权限</span><input id="menu-filter-keyword" name="menuKeyword" value={@menu_filter} placeholder="按名称、编码或权限筛选" autocomplete="off" /></label>
          <div class="menus-filter-actions"><button type="submit" class="button button-primary button-sm"><.nav_icon name="search" />查询</button><button type="button" class="button button-ghost button-sm" phx-click="refresh-menus" phx-value-reset="true">重置</button></div>
        </form>
      </section>
      <%= if @active_modal == "menu" do %>
        <.modal id="menu-modal" title={if @menu_form["menuId"] == "", do: "新增菜单", else: "编辑菜单"} description="菜单权限会由系统 API 按当前主体权限再次校验。">
    <p :if={@menu_feedback} id="menu-feedback" class={Feedback.class(@menu_feedback)} role={Feedback.role(@menu_feedback)} aria-live={Feedback.live(@menu_feedback)}><%= Feedback.message(@menu_feedback) %><small :if={Feedback.code(@menu_feedback)}>错误码：<%= Feedback.code(@menu_feedback) %></small></p>
    <form :if={!@read_only} aria-describedby="menu-feedback" phx-submit="save-menu">
        <input type="hidden" name="menuId" value={@menu_form["menuId"]} />
        <div class="form-grid">
          <div><label for="menu-name">菜单名称</label><input id="menu-name" name="name" value={@menu_form["name"] || @menu_form["menuName"]} required /></div><div><label for="menu-code">菜单编码</label><input id="menu-code" name="code" value={@menu_form["code"] || @menu_form["menuCode"]} required /></div><div><label for="menu-parent">上级菜单</label><select id="menu-parent" name="parentId"><option value="">根菜单</option><%= for parent <- OrganizationFilters.menu_parent_rows(@menu_rows, @menu_form["menuId"]) do %><option value={parent["menuId"] || parent["id"]} selected={to_string(@menu_form["parentId"] || "") == to_string(parent["menuId"] || parent["id"])}><%= String.duplicate("　", parent["depth"] || 0) %><%= parent["name"] || parent["menuName"] %></option><% end %></select></div><div><label for="menu-type">菜单类型</label><select id="menu-type" name="menuType"><option value="MENU" selected={@menu_form["menuType"] in [1, "1", "MENU"]}>菜单</option><option value="BUTTON" selected={@menu_form["menuType"] in [0, "0", "BUTTON"]}>按钮</option><option value="DIRECTORY" selected={@menu_form["menuType"] in [2, "2", "DIRECTORY"]}>目录</option></select></div><div><label for="menu-path">路由路径</label><input id="menu-path" name="path" value={@menu_form["path"] || ""} placeholder="/system/users" /></div><div><label for="menu-component">组件路径</label><input id="menu-component" name="component" value={@menu_form["component"] || @menu_form["routerName"] || ""} placeholder="system/users/index" /></div><div><label for="menu-permission">权限标识</label><input id="menu-permission" name="permission" value={@menu_form["permission"] || ""} placeholder="user:read" /></div><div><label for="menu-sort">排序</label><input id="menu-sort" type="number" min="0" name="sortOrder" value={@menu_form["sortOrder"] || 0} /></div>
          <div class="wide"><input type="hidden" name="enabled" value="false" /><label class="checkbox-label" for="menu-enabled"><input id="menu-enabled" type="checkbox" name="enabled" value="true" checked={@menu_form["enabled"] in [true, 1, "true", "1"]} /><span>启用菜单</span></label></div>
        </div>
        <fieldset :if={"menu:manage" in @permissions} id="menu-role-codes" class="menu-role-access">
          <legend>可访问角色</legend>
          <%!-- 已绑定的停用角色可保留或移除，未绑定停用角色不能新增。 --%>
          <% selected_codes = Enum.map(@menu_role_codes, &to_string/1) %>
          <% visible_roles = Enum.filter(@role_rows, &(&1["status"] in [1, "1", true] or to_string(&1["roleKey"] || &1["code"]) in selected_codes)) %>
          <% visible_codes = Enum.map(visible_roles, &to_string(&1["roleKey"] || &1["code"])) %>
          <% missing_codes = selected_codes -- visible_codes %>
          <%= if visible_roles == [] and missing_codes == [] do %>
            <p class="form-help">暂无启用角色可分配。</p>
          <% else %>
            <div class="menu-role-options">
              <%= for role <- visible_roles do %>
                <% role_code = role["roleKey"] || role["code"] %>
                <label class="checkbox-label"><input type="checkbox" name="menuRoleCodes[]" value={role_code} checked={to_string(role_code) in selected_codes} /><span><%= role["roleName"] || role["name"] || role_code %> <small><%= role_code %><%= if role["status"] not in [1, "1", true], do: " · 已停用" %></small></span></label>
              <% end %>
              <%= for role_code <- missing_codes do %>
                <label class="checkbox-label"><input type="checkbox" name="menuRoleCodes[]" value={role_code} checked /><span><%= role_code %> <small>角色详情不可读取</small></span></label>
              <% end %>
            </div>
          <% end %>
          <p class="form-help">保存后会替换该菜单的角色绑定。未选择角色时，菜单不会显示给任何角色。</p>
        </fieldset>
        <div class="form-actions"><button type="submit" phx-disable-with="保存中…">保存菜单</button><button :if={@menu_form["menuId"] != ""} type="button" class="secondary" phx-click="close-modal" phx-value-modal="menu" phx-disable-with="处理中…">取消编辑</button></div>
      </form>
        </.modal>
      <% end %>
      <section class="card table-card menus-table-card" aria-labelledby="menus-table-title">
        <.list_toolbar label="菜单列表操作">
          <button :if={!@read_only} type="button" class="button button-primary button-sm" phx-click="new-menu" phx-disable-with="处理中…"><.nav_icon name="plus" />新增菜单</button>
          <button type="button" class="button button-secondary button-sm" phx-click="refresh-menus" phx-disable-with="刷新中…"><.nav_icon name="refresh" />刷新菜单</button>
        </.list_toolbar>
        <div class="card-header">
          <div>
            <h2 id="menus-table-title">菜单目录</h2>
            <p>当前匹配 <%= length(OrganizationFilters.filtered_menus(@menu_rows, @menu_filter)) %> 个菜单节点。</p>
          </div>
          <span class="badge badge-info">系统 API</span>
        </div>
        <%= if OrganizationFilters.filtered_menus(@menu_rows, @menu_filter) == [] do %>
          <div class="menus-empty" role="status"><strong>没有匹配的菜单</strong><p>调整筛选条件后重试，或清空筛选条件查看完整菜单。</p></div>
        <% else %>
        <div class="menus-table-wrap"><table class="menus-table"><caption class="sr-only">菜单列表</caption><thead><tr><th scope="col">菜单名称</th><th scope="col">编码</th><th scope="col">路由</th><th scope="col">权限标识</th><th scope="col">类型</th><th scope="col">状态</th><th scope="col">操作</th></tr></thead><tbody><%= for menu <- OrganizationFilters.filtered_menus(@menu_rows, @menu_filter) do %><tr data-menu-id={menu["menuId"] || menu["id"]} data-parent-menu-id={menu["parentId"]}><td><div class="menu-cell" style={"--menu-depth: #{menu["depth"] || 0}"} data-menu-depth={menu["depth"] || 0}><span class="menu-marker" aria-hidden="true"><.nav_icon name="list-tree" /></span><strong><%= menu["name"] || menu["menuName"] %></strong></div></td><td class="menu-code"><%= menu["code"] || menu["menuCode"] || menu["menuId"] %></td><td class="menu-path"><%= menu["path"] || "—" %></td><td class="menu-permission"><%= menu["permission"] || "—" %></td><td><span class="badge badge-neutral"><%= menu["menuTypeStr"] || OrganizationData.menu_type_label(menu["menuType"], menu["isButton"]) %></span></td><td><span class={"status-badge #{Status.normal_paused(if(OrganizationData.menu_enabled?(menu), do: 1, else: 0))}"}><%= if OrganizationData.menu_enabled?(menu), do: "启用", else: "停用" %></span></td><td :if={!@read_only} class="table-actions"><button type="button" class="button button-ghost button-sm" phx-click="edit-menu" phx-value-menu-id={menu["menuId"] || menu["id"]} phx-disable-with="加载中…">编辑</button><button type="button" class="button button-ghost button-sm" phx-confirm="确认删除此菜单吗？" phx-click="delete-menu" phx-value-menu-id={menu["menuId"] || menu["id"]} phx-disable-with="删除中…">删除</button></td></tr><% end %></tbody></table></div>
        <% end %>
      </section>
    </div>
    """
  end

  @doc "返回当前 LiveView 主体可以授予的角色权限目录。"
  def role_permission_entries(permissions) do
    allowed = MapSet.new(List.wrap(permissions))

    PermissionCatalog.entries()
    |> Enum.filter(fn entry ->
      entry.registered? and MapSet.member?(allowed, entry.permission)
    end)
  end

  # 新建和编辑按钮按各自权限显示，避免用管理员身份替代业务权限判断。
  def role_form_allowed?(form, permissions) do
    permission =
      if String.trim(to_string(form["roleId"] || "")) == "",
        do: "role:create",
        else: "role:update"

    permission in List.wrap(permissions)
  end

  # 两种角色编辑入口共享权限清单，但事件会分别更新对应的服务端表单状态。
  defp role_permission_picker(assigns) do
    ~H"""
    <div class="api-key-scope-groups role-permission-picker">
      <%= for {resource, entries} <- grouped_role_permission_entries(role_permission_entries(@permissions), @query) do %>
        <section class="api-key-scope-group">
          <h4><%= role_permission_resource_label(resource) %></h4>
          <div>
            <%= for entry <- entries do %>
              <label class="checkbox-label">
                <input type="checkbox" phx-click="toggle-role-permission" phx-value-permission={entry.permission} phx-value-selected={if role_permission_selected?(@selected, entry.permission), do: "false", else: "true"} checked={role_permission_selected?(@selected, entry.permission)} />
                <span><%= role_permission_action_label(entry.action) %></span><code><%= entry.permission %></code>
              </label>
            <% end %>
          </div>
        </section>
      <% end %>
      <p :if={role_permission_entries(@permissions) == []} class="form-help" role="status">没有可配置的权限。</p>
      <small>权限目录来自当前账号可授予的权限。</small>
    </div>
    """
  end

  @doc "按资源分组并筛选角色权限目录。"
  def grouped_role_permission_entries(entries, query) do
    normalized = String.downcase(String.trim(to_string(query)))

    entries
    |> Enum.filter(fn entry ->
      normalized == "" or
        String.contains?(
          String.downcase("#{entry.permission} #{entry.description} #{entry.action}"),
          normalized
        )
    end)
    |> Enum.group_by(& &1.resource)
    |> Enum.sort_by(&elem(&1, 0))
  end

  def role_permission_selected?(permissions, permission),
    do: permission in String.split(to_string(permissions || ""), ",", trim: true)

  def role_permission_resource_label("api-key"), do: "API Key"
  def role_permission_resource_label("user"), do: "用户管理"
  def role_permission_resource_label("role"), do: "角色管理"
  def role_permission_resource_label("menu"), do: "菜单与权限"
  def role_permission_resource_label("job"), do: "定时任务"
  def role_permission_resource_label("notice"), do: "通知公告"
  def role_permission_resource_label("dictionary"), do: "字典管理"
  def role_permission_resource_label("department"), do: "组织结构"
  def role_permission_resource_label("post"), do: "岗位管理"
  def role_permission_resource_label(resource), do: resource

  def role_permission_action_label("create"), do: "新增"
  def role_permission_action_label("delete"), do: "删除"
  def role_permission_action_label("read"), do: "读取"
  def role_permission_action_label("update"), do: "修改"
  def role_permission_action_label("export"), do: "导出"
  def role_permission_action_label("import"), do: "导入"
  def role_permission_action_label("manage"), do: "管理"
  def role_permission_action_label("refresh"), do: "刷新"
  def role_permission_action_label("revoke"), do: "撤销"
  def role_permission_action_label("rotate"), do: "轮换"
  def role_permission_action_label("run"), do: "执行"
  def role_permission_action_label("assign"), do: "分配"
  def role_permission_action_label("reset-password"), do: "重置密码"
  def role_permission_action_label("update-status"), do: "修改状态"
  def role_permission_action_label(action), do: action
end
