defmodule KeystonePhoenixWeb.AdminNoticeTypeLiveIntegrationTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.Notice
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  setup do
    username = "notice_type_admin_#{System.unique_integer([:positive])}"
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    {:ok, user} =
      %SysUser{}
      |> SysUser.create_changeset(%{
        "username" => username,
        "nickname" => "公告类型管理员",
        "password" => "Strong!123",
        "role_id" => role.role_id,
        "status" => 1
      })
      |> Repo.insert()

    {:ok, admin: user}
  end

  @tag :integration
  test "LiveView 创建、更新、筛选并回读自由公告类型", %{conn: conn, admin: admin} do
    suffix = System.unique_integer([:positive])
    title = "LiveView 自由类型公告 #{suffix}"
    custom_type = "live.custom.type.#{suffix}"
    updated_type = String.duplicate("u", 32)

    {:ok, view, _html} = live(conn, "/")

    render_submit(view, "login", %{
      "username" => admin.username,
      "password" => "Strong!123"
    })

    render_click(view, "show-panel", %{"panel" => "notices"})
    render_click(view, "new-notice")

    assert has_element?(view, "input#notice-type[value='announcement']")
    refute has_element?(view, "input#notice-type[maxlength]")
    refute has_element?(view, "select#notice-type")

    render_submit(view, "save-notice", %{
      "noticeId" => "",
      "noticeTitle" => title,
      "noticeType" => custom_type,
      "noticeContent" => "自由公告类型内容",
      "status" => "1",
      "remark" => ""
    })

    assert render(view) =~ "公告已创建"

    created =
      Notice.list_notices(%{"keyword" => title, "pageSize" => 10}).rows
      |> List.first()

    assert created["noticeType"] == custom_type
    assert Notice.list_notices_page(%{"title" => custom_type}).total == 0
    assert Notice.list_notices_page(%{"keyword" => custom_type}).total == 1

    render_submit(view, "filter-notices", %{
      "noticeTitle" => "custom.type.#{suffix}",
      "published" => "all"
    })

    assert render(view) =~ custom_type
    assert render(view) =~ "共 1 条匹配公告"

    render_click(view, "edit-notice", %{"notice-id" => to_string(created["noticeId"])})

    render_submit(view, "save-notice", %{
      "noticeId" => to_string(created["noticeId"]),
      "noticeTitle" => title,
      "noticeType" => updated_type,
      "noticeContent" => "自由公告类型已更新",
      "status" => "1",
      "remark" => ""
    })

    assert render(view) =~ "公告已更新"

    render_submit(view, "filter-notices", %{
      "noticeTitle" => title,
      "published" => "all"
    })

    assert render(view) =~ updated_type

    readback =
      Notice.list_notices(%{"keyword" => title, "pageSize" => 10}).rows
      |> List.first()

    assert readback["noticeType"] == updated_type
  end

  # 输入框不设置 maxlength，避免浏览器按 UTF-16 单元截断；服务端按 Unicode 码点限制。
  @tag :integration
  test "LiveView 接受 32 个 Unicode 码点的公告类型", %{conn: conn, admin: admin} do
    suffix = System.unique_integer([:positive])
    title = "LiveView Unicode 边界公告 #{suffix}"
    notice_type = String.duplicate("😀", 32)

    {:ok, view, _html} = live(conn, "/")

    render_submit(view, "login", %{
      "username" => admin.username,
      "password" => "Strong!123"
    })

    render_click(view, "show-panel", %{"panel" => "notices"})
    render_click(view, "new-notice")

    refute has_element?(view, "input#notice-type[maxlength]")

    render_submit(view, "save-notice", %{
      "noticeId" => "",
      "noticeTitle" => title,
      "noticeType" => notice_type,
      "noticeContent" => "Unicode 码点边界内容",
      "status" => "1",
      "remark" => ""
    })

    assert render(view) =~ "公告已创建"

    saved =
      Notice.list_notices(%{"keyword" => title, "pageSize" => 10}).rows
      |> List.first()

    assert saved["noticeType"] == notice_type
  end

  @tag :integration
  test "公告已创建但列表刷新失败时关闭表单并保留可刷新的旧列表", %{
    conn: conn,
    admin: admin
  } do
    suffix = System.unique_integer([:positive])
    old_title = "刷新前公告 #{suffix}"
    new_title = "刷新失败后公告 #{suffix}"
    {:ok, view, _html} = live(conn, "/")

    render_submit(view, "login", %{
      "username" => admin.username,
      "password" => "Strong!123"
    })

    render_click(view, "show-panel", %{"panel" => "notices"})
    render_click(view, "new-notice")
    render_submit(view, "save-notice", notice_params(old_title))

    assert render(view) =~ old_title

    install_notice_rename_trigger()

    try do
      render_click(view, "new-notice")
      html = render_submit(view, "save-notice", notice_params(new_title))

      assert html =~ "公告已创建，但列表刷新失败；旧列表仍保留，请点击“刷新公告”重试。"
      refute has_element?(view, "#notice-modal")
      assert html =~ old_title
      refute html =~ new_title

      assert Repo.query!(
               "SELECT COUNT(*) FROM sys_notice_unavailable WHERE notice_title = $1",
               [new_title]
             ).rows == [[1]]
    after
      restore_notice_table()
    end

    html = render_click(view, "refresh-notices")
    assert html =~ old_title
    assert html =~ new_title
    refute html =~ "列表刷新失败"
  end

  defp notice_params(title) do
    %{
      "noticeId" => "",
      "noticeTitle" => title,
      "noticeType" => "announcement",
      "noticeContent" => "公告写入结果验收",
      "status" => "1",
      "remark" => ""
    }
  end

  # 仅在隔离测试数据库中让写入触发重命名，随后列表查询会真实遇到缺失表。
  defp install_notice_rename_trigger do
    Repo.query!("""
    CREATE FUNCTION test_rename_sys_notice_after_insert() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      EXECUTE 'ALTER TABLE sys_notice RENAME TO sys_notice_unavailable';
      RETURN NEW;
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER test_rename_sys_notice_after_insert
    AFTER INSERT ON sys_notice
    FOR EACH ROW EXECUTE FUNCTION test_rename_sys_notice_after_insert()
    """)
  end

  # 恢复关系名后，测试事务结束时会一起回滚临时触发器和数据库对象。
  defp restore_notice_table do
    case Repo.query!("SELECT to_regclass('public.sys_notice_unavailable')").rows do
      [[nil]] ->
        :ok

      [[_relation]] ->
        Repo.query!("DROP TRIGGER test_rename_sys_notice_after_insert ON sys_notice_unavailable")
        Repo.query!("ALTER TABLE sys_notice_unavailable RENAME TO sys_notice")
        Repo.query!("DROP FUNCTION test_rename_sys_notice_after_insert()")
    end
  end
end
