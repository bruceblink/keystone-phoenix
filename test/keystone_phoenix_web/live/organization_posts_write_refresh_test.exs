defmodule KeystonePhoenixWeb.OrganizationPostsWriteRefreshTest do
  @moduledoc "验证岗位写入后的真实分页刷新，以及 PostgreSQL 读取失败时的部分成功反馈。"

  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import KeystonePhoenixWeb.LiveAuthenticationTestSupport, only: [live_socket: 1, login_view: 2]

  alias KeystonePhoenix.{Identity, Repo}
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Post.SysPost
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  setup do
    role =
      %SysRole{role_id: Identity.v7()}
      |> SysRole.changeset(%{
        role_name: unique("岗位刷新管理员"),
        role_key: unique("post_refresh_admin"),
        role_sort: 1,
        data_scope: "ALL",
        dept_id_set: "",
        status: 1
      })
      |> Repo.insert!()

    for permission <- Repo.all(SysPermission) do
      Repo.insert!(%SysRolePermission{
        role_id: role.role_id,
        permission_id: permission.permission_id
      })
    end

    admin =
      Repo.insert!(%SysUser{
        user_id: Identity.v7(),
        role_id: role.role_id,
        username: unique("post_refresh_admin"),
        password: Bcrypt.hash_pwd_salt("Strong!123"),
        status: 1
      })

    {:ok, admin: admin}
  end

  test "saving a post retains the active filter and refreshes rows and total", ctx do
    create_post("target-existing")
    create_post("unrelated-row")
    {:ok, view, _html} = login_view(ctx.conn, ctx.admin)
    open_filtered_posts(view, "target-")

    render_click(view, "new-post")
    assert has_element?(view, "button[type='submit'][phx-disable-with='保存中…']")

    view
    |> form("form[phx-submit='save-post']", %{
      "postCode" => unique("target-created"),
      "postName" => "筛选内新岗位",
      "postSort" => "3",
      "status" => "1"
    })
    |> render_submit()

    assigns = live_socket(view).assigns
    assert assigns.post_feedback == "岗位已创建"
    assert assigns.active_modal == nil
    assert assigns.post_form["postId"] == ""
    assert assigns.post_filter["keyword"] == "target-"
    assert assigns.post_total == 2
    assert length(assigns.post_rows) == 2
    assert Enum.all?(assigns.post_rows, &String.starts_with?(&1["postCode"], "target-"))
    assert assigns.page_nums["posts"] == 1
    assert assigns.page_sizes["posts"] == 20
  end

  test "saving an edited post does not replace filtered rows with the full list", ctx do
    post = create_post("target-edit")
    create_post("unrelated-edit")
    {:ok, view, _html} = login_view(ctx.conn, ctx.admin)
    open_filtered_posts(view, "target-edit")

    render_click(view, "edit-post", %{"post-id" => to_string(post.post_id)})

    view
    |> form("form[phx-submit='save-post']", %{"postName" => "岗位名称已更新"})
    |> render_submit()

    assigns = live_socket(view).assigns
    assert assigns.post_feedback == "岗位已更新"
    assert assigns.post_filter["keyword"] == "target-edit"
    assert assigns.post_total == 1
    assert length(assigns.post_rows) == 1
    assert hd(assigns.post_rows)["postName"] == "岗位名称已更新"
    assert to_string(hd(assigns.post_rows)["postId"]) == to_string(post.post_id)
    assert assigns.page_nums["posts"] == 1
  end

  test "status changes retain both keyword and status filters and refresh the total", ctx do
    post = create_post("target-status", 1)
    create_post("unrelated-status", 1)
    {:ok, view, _html} = login_view(ctx.conn, ctx.admin)
    render_click(view, "show-panel", %{"panel" => "posts"})

    render_submit(view, "refresh-posts", %{
      "postKeyword" => "target-status",
      "postStatus" => "1"
    })

    render_click(view, "toggle-post-status", %{
      "post-id" => to_string(post.post_id),
      "status" => "0"
    })

    assigns = live_socket(view).assigns
    assert assigns.post_filter == %{"keyword" => "target-status", "status" => "1"}
    assert assigns.post_feedback == "岗位状态已更新"
    assert assigns.post_rows == []
    assert assigns.post_total == 0
    assert assigns.page_nums["posts"] == 1
  end

  test "deleting a filtered post refreshes its rows and total", ctx do
    post = create_post("target-delete")
    create_post("unrelated-delete")
    {:ok, view, _html} = login_view(ctx.conn, ctx.admin)
    open_filtered_posts(view, "target-delete")

    render_click(view, "delete-post", %{"post-id" => to_string(post.post_id)})

    assigns = live_socket(view).assigns
    assert assigns.post_filter["keyword"] == "target-delete"
    assert assigns.post_feedback == "岗位已删除"
    assert assigns.post_rows == []
    assert assigns.post_total == 0
    assert assigns.page_nums["posts"] == 1
    assert assigns.active_modal == nil
  end

  test "a successful insert with a failed list read keeps old rows and reports partial success",
       ctx do
    Enum.each(1..21, &create_post("target-existing-read-failure-#{&1}"))
    create_post("unrelated-read-failure")
    {:ok, view, _html} = login_view(ctx.conn, ctx.admin)
    open_filtered_posts(view, "target-existing-read-failure")
    render_click(view, "paginate", %{"panel" => "posts", "page" => "2"})
    old_rows = live_socket(view).assigns.post_rows
    assert length(old_rows) == 1
    assert live_socket(view).assigns.page_nums["posts"] == 2
    install_post_read_failure_after_insert()

    render_click(view, "new-post")

    html =
      view
      |> form("form[phx-submit='save-post']", %{
        "postCode" => unique("target-created-read-failure"),
        "postName" => "已保存但列表暂不可读",
        "postSort" => "4",
        "status" => "1"
      })
      |> render_submit()

    assigns = live_socket(view).assigns
    assert html =~ "岗位已创建，但列表刷新失败"
    assert html =~ "当前保留旧列表"
    assert assigns.active_modal == nil
    assert assigns.post_form["postId"] == ""

    assert assigns.post_rows == old_rows
    assert assigns.post_total == 21
    assert assigns.post_filter["keyword"] == "target-existing-read-failure"
    assert assigns.page_nums["posts"] == 2

    assert KeystonePhoenixWeb.Live.AdminPages.Feedback.code(assigns.post_feedback) ==
             "service_unavailable"
  end

  defp open_filtered_posts(view, keyword) do
    render_click(view, "show-panel", %{"panel" => "posts"})
    render_submit(view, "refresh-posts", %{"postKeyword" => keyword, "postStatus" => "all"})
  end

  defp create_post(code, status \\ 1) do
    %SysPost{post_id: Identity.v7()}
    |> SysPost.changeset(%{
      post_code: code,
      post_name: "岗位 #{code}",
      post_sort: 1,
      status: status
    })
    |> Repo.insert!()
  end

  defp install_post_read_failure_after_insert do
    role_name = unique("post_list_reader")

    # 触发器在岗位写入完成后撤销列表读取权限，用真实 PostgreSQL 错误验证部分成功状态。
    Repo.query!("CREATE ROLE #{role_name} NOLOGIN")
    Repo.query!("GRANT ALL ON ALL TABLES IN SCHEMA public TO #{role_name}")
    Repo.query!("GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO #{role_name}")

    Repo.query!("""
    CREATE FUNCTION revoke_test_post_read_after_insert()
    RETURNS trigger
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_catalog, public
    AS $$
    BEGIN
      EXECUTE 'REVOKE SELECT ON TABLE public.sys_post FROM #{role_name}';
      RETURN NEW;
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER revoke_test_post_read_after_insert
    AFTER INSERT ON public.sys_post
    FOR EACH ROW EXECUTE FUNCTION public.revoke_test_post_read_after_insert()
    """)

    Repo.query!("SET LOCAL ROLE #{role_name}")
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
