defmodule KeystonePhoenixWeb.AdminApiKeyExpiryTimerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ExUnit.Assertions

  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenix.Auth.ApiKey.Key
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Live.AdminEvents.ApiKeyExpiryTimer
  alias KeystonePhoenixWeb.Live.AdminEvents.Security
  alias KeystonePhoenixWeb.LiveAuthenticationTestSupport, as: LiveSupport

  @password "Strong!123"

  @tag :integration
  test "全部状态页面在密钥到期时更新徽标并禁用轮换", %{conn: conn} do
    owner = create_admin_user("expiry_all")
    key = issue_key(owner, "全部状态到期密钥")
    {:ok, view, _html} = live(conn, "/")
    login(view, owner)
    render_click(view, "show-panel", %{"panel" => "api-keys"})
    set_expiry(key, 4)
    render_click(view, "refresh-api-keys")

    assert has_element?(view, "tr .status-badge--success", "有效")

    assert has_element?(
             view,
             "button[phx-click='rotate-api-key'][phx-value-id='#{key.id}']:not([disabled])"
           )

    assert_eventually(fn ->
      render(view)

      has_element?(view, "tr .status-badge--paused", "已过期") and
        has_element?(
          view,
          "button[phx-click='rotate-api-key'][phx-value-id='#{key.id}'][disabled]"
        )
    end)

    assert LiveSupport.live_socket(view).assigns.api_key_total == 1
  end

  @tag :integration
  test "有效筛选中多个密钥到期后依次移出列表", %{conn: conn} do
    owner = create_admin_user("expiry_multiple")
    first = issue_key(owner, "短期密钥一")
    second = issue_key(owner, "短期密钥二")
    {:ok, view, _html} = live(conn, "/")
    login(view, owner)
    render_click(view, "show-panel", %{"panel" => "api-keys"})

    set_expiry(first, 3)
    set_expiry(second, 5)
    render_click(view, "refresh-api-keys")
    render_submit(view, "filter-api-keys", %{"query" => "", "status" => "active"})

    assert has_element?(view, "tr", "短期密钥一")
    assert has_element?(view, "tr", "短期密钥二")
    assert LiveSupport.live_socket(view).assigns.api_key_total == 2

    assert_eventually(fn ->
      render(view)

      not has_element?(view, "tr", "短期密钥一") and
        has_element?(view, "tr", "短期密钥二") and
        LiveSupport.live_socket(view).assigns.api_key_total == 1
    end)

    assert_eventually(fn ->
      render(view)

      not has_element?(view, "tr", "短期密钥二") and
        LiveSupport.live_socket(view).assigns.api_key_total == 0
    end)
  end

  @tag :integration
  test "到期重读失败时保留旧行和错误提示，恢复后可重试", %{conn: conn} do
    owner = create_admin_user("expiry_failure")
    key = issue_key(owner, "故障恢复密钥")
    {:ok, view, _html} = live(conn, "/")
    login(view, owner)
    render_click(view, "show-panel", %{"panel" => "api-keys"})
    set_expiry(key, 3)
    render_click(view, "refresh-api-keys")
    render_submit(view, "filter-api-keys", %{"query" => "", "status" => "active"})

    expires_at = Repo.get!(Key, key.id).expires_at
    unavailable_table = "sys_api_key_unavailable_#{System.unique_integer([:positive])}"

    # 隔离数据库临时隐藏密钥表，验证到期后的自动读取失败和手动恢复入口。
    Repo.query!("ALTER TABLE sys_api_key RENAME TO #{unavailable_table}")

    try do
      assert_eventually(fn ->
        render(view)
        assigns = LiveSupport.live_socket(view).assigns

        match?({:error, _, _}, assigns.api_key_feedback) and
          DateTime.compare(assigns.api_key_now, expires_at) != :lt
      end)

      assert has_element?(view, "tr", "故障恢复密钥")
      assert has_element?(view, "tr .status-badge--paused", "已过期")
      assert has_element?(view, "#api-key-feedback[role='alert']", "API Key 列表刷新失败")
      assert LiveSupport.live_socket(view).assigns.api_key_total == 1
    after
      Repo.query!("ALTER TABLE #{unavailable_table} RENAME TO sys_api_key")
    end

    render_click(view, "refresh-api-keys")
    refute has_element?(view, "tr", "故障恢复密钥")
    assert has_element?(view, ".api-keys-empty")
    assert LiveSupport.live_socket(view).assigns.api_key_total == 0
  end

  @tag :integration
  test "切页取消到期计时，结束 LiveView 也会清理计时", %{conn: conn} do
    owner = create_admin_user("expiry_cancel")
    key = issue_key(owner, "导航取消密钥")
    {:ok, view, _html} = live(conn, "/")
    login(view, owner)
    render_click(view, "show-panel", %{"panel" => "api-keys"})
    set_expiry(key, 60)
    render_click(view, "refresh-api-keys")

    api_socket = LiveSupport.live_socket(view)
    timer = api_socket.assigns.api_key_expiry_timer
    token = api_socket.assigns.api_key_expiry_token
    assert is_reference(timer)
    assert is_reference(token)

    render_click(view, "refresh-api-keys")
    renewed_socket = LiveSupport.live_socket(view)
    renewed_token = renewed_socket.assigns.api_key_expiry_token
    unchanged_time = renewed_socket.assigns.api_key_now
    assert renewed_token != token
    assert Process.read_timer(timer) == false

    Process.sleep(2)
    send(view.pid, {:api_key_expiry_tick, token})
    ignored_socket = LiveSupport.live_socket(view)
    assert ignored_socket.assigns.api_key_expiry_token == renewed_token
    assert ignored_socket.assigns.api_key_now == unchanged_time

    render_click(view, "show-panel", %{"panel" => "roles"})
    roles_socket = LiveSupport.live_socket(view)
    assert is_nil(roles_socket.assigns.api_key_expiry_timer)
    assert Process.read_timer(timer) == false

    send(view.pid, {:api_key_expiry_tick, token})

    assert_eventually(fn ->
      assigns = LiveSupport.live_socket(view).assigns
      assigns.active_panel == "roles" and assigns.api_key_expiry_timer == nil
    end)

    render_click(view, "show-panel", %{"panel" => "api-keys"})
    closing_timer = LiveSupport.live_socket(view).assigns.api_key_expiry_timer
    monitor = Process.monitor(view.pid)
    trap_exit = Process.flag(:trap_exit, true)

    try do
      :sys.terminate(view.pid, :shutdown)
      assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, 1_000
      assert_receive {:EXIT, _, :shutdown}, 1_000
      assert Process.read_timer(closing_timer) == false
    after
      Process.flag(:trap_exit, trap_exit)
    end
  end

  test "长到期时间提前醒来后重设计时，旧令牌不刷新列表" do
    # 直接向回调发送有效的远期计时消息，不等待数周即可覆盖上限重设路径。
    expiry = DateTime.add(DateTime.utc_now(), 60 * 24 * 60 * 60, :second)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        active_panel: "api-keys",
        api_key_status: "all",
        api_key_now: DateTime.utc_now(),
        api_key_expiry_timer: nil,
        api_key_expiry_token: nil,
        api_key_rows: [%{expires_at: expiry, revoked_at: nil}]
      }
    }

    scheduled = ApiKeyExpiryTimer.schedule(socket, expiry)
    timer = scheduled.assigns.api_key_expiry_timer
    token = scheduled.assigns.api_key_expiry_token
    assert Process.read_timer(timer) in 1..2_147_483_647
    Process.cancel_timer(timer)

    {:noreply, rescheduled} = Security.handle_info({:api_key_expiry_tick, token}, scheduled)
    assert rescheduled.assigns.api_key_expiry_token != token
    assert Process.read_timer(rescheduled.assigns.api_key_expiry_timer) in 1..2_147_483_647

    {:noreply, unchanged} = Security.handle_info({:api_key_expiry_tick, token}, rescheduled)
    assert unchanged == rescheduled
    ApiKeyExpiryTimer.cancel(rescheduled)
  end

  test "全部状态筛选只更新时间，过期行仍保留" do
    now = DateTime.utc_now()
    token = make_ref()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        active_panel: "api-keys",
        api_key_status: "all",
        api_key_now: DateTime.add(now, -2, :second),
        api_key_expiry_timer: nil,
        api_key_expiry_token: token,
        api_key_feedback: "保留当前反馈",
        api_key_rows: [%{expires_at: DateTime.add(now, -1, :second), revoked_at: nil}]
      }
    }

    {:noreply, refreshed} = Security.handle_info({:api_key_expiry_tick, token}, socket)
    assert DateTime.compare(refreshed.assigns.api_key_now, now) != :lt
    assert refreshed.assigns.api_key_rows == socket.assigns.api_key_rows
    assert refreshed.assigns.api_key_feedback == "保留当前反馈"
    assert is_nil(refreshed.assigns.api_key_expiry_timer)
  end

  defp create_admin_user(prefix) do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    %SysUser{}
    |> SysUser.create_changeset(%{
      "username" => "#{prefix}_#{System.unique_integer([:positive])}",
      "nickname" => "API Key 到期验收管理员",
      "password" => @password,
      "role_id" => role.role_id,
      "status" => 1
    })
    |> Repo.insert!()
  end

  defp issue_key(owner, name) do
    assert {:ok, issued} = ApiKey.issue(owner.user_id, name, ["api-key:read"])
    issued
  end

  defp set_expiry(key, seconds) do
    key.id
    |> then(&Repo.get!(Key, &1))
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), seconds, :second))
    |> Repo.update!()
  end

  defp login(view, user) do
    render_submit(view, "login", %{"username" => user.username, "password" => @password})
    refute has_element?(view, "#login-form")
  end

  defp assert_eventually(fun, attempts \\ 300)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(_fun, 0), do: flunk("预期的 LiveView 计时事件未完成")
end
