defmodule KeystonePhoenix.Auth.RefreshConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.SysUser

  test "allows at most one independent connection to rotate one refresh token" do
    fixture = create_fixture()
    lock_holder = hold_refresh_row(fixture.jti)

    on_exit(fn ->
      {locker_pid, _locker_ref} = lock_holder
      send(locker_pid, :release)
      await_task(lock_holder)

      with_unboxed(fn ->
        Repo.delete_all(
          from(session in KeystonePhoenix.Auth.AuthSession,
            where: session.user_id == ^fixture.user_id
          )
        )

        Repo.delete_all(from(user in SysUser, where: user.user_id == ^fixture.user_id))
      end)
    end)

    test_pid = self()

    tasks =
      Enum.map(1..2, fn _ ->
        spawn_monitor(fn ->
          receive do
            {:refresh, result_ref} ->
              result = with_unboxed(fn -> Auth.refresh(fixture.refresh_token) end)
              send(test_pid, {result_ref, result})
          end
        end)
      end)

    task_refs = Enum.map(tasks, fn {_pid, _monitor_ref} -> make_ref() end)
    Enum.zip(tasks, task_refs) |> Enum.each(fn {{pid, _}, ref} -> send(pid, {:refresh, ref}) end)

    assert_receive {:refresh_row_locked, _locker_pid}, 5_000
    waiter_result = await_refresh_waiters(System.monotonic_time(:millisecond) + 15_000)

    original_session_active =
      with_unboxed(fn -> Auth.Session.active?(fixture.user_id, fixture.jti) end)

    {locker_pid, _locker_ref} = lock_holder
    send(locker_pid, :release)

    raw_results =
      Enum.zip(tasks, task_refs)
      |> Enum.map(fn {{pid, monitor_ref}, result_ref} ->
        await_result(pid, monitor_ref, result_ref)
      end)

    results = Enum.map(raw_results, &classify_result/1)

    assert :ok = waiter_result
    assert original_session_active
    assert Enum.sort(results) == [:ok, {:error, :invalid_refresh_token}]

    assert {:ok, winning_tokens} =
             Enum.find_value(raw_results, fn
               {:ok, tokens} -> {:ok, tokens}
               _ -> nil
             end)

    winning_refresh_token = winning_tokens.refresh_token

    assert {:ok, claims} =
             KeystonePhoenix.Auth.Token.verify(
               winning_refresh_token,
               KeystonePhoenix.Auth.Token.refresh_type()
             )

    # 并发请求中的旧令牌会被视为重用，整个刷新族必须撤销。
    refute with_unboxed(fn -> Auth.Session.active?(fixture.user_id, claims["jti"]) end)
    assert {:error, :invalid_token} = Auth.authenticate_access_token(winning_tokens.token)
  end

  test "password reset cannot leave a session created by an overlapping refresh" do
    fixture = create_fixture()
    lock_holder = hold_user_lock(fixture.user_id)

    on_exit(fn ->
      release_lock_holder(lock_holder)
      await_task(lock_holder)

      with_unboxed(fn ->
        Repo.delete_all(
          from(session in KeystonePhoenix.Auth.AuthSession,
            where: session.user_id == ^fixture.user_id
          )
        )

        Repo.delete_all(from(user in SysUser, where: user.user_id == ^fixture.user_id))
      end)
    end)

    test_pid = self()
    refresh_ref = make_ref()

    refresh_task =
      spawn_monitor(fn ->
        result = with_unboxed(fn -> Auth.refresh(fixture.refresh_token) end)
        send(test_pid, {refresh_ref, result})
      end)

    assert :ok = await_advisory_waiters(1, System.monotonic_time(:millisecond) + 15_000)

    reset_ref = make_ref()

    reset_task =
      spawn_monitor(fn ->
        result =
          with_unboxed(fn ->
            User.reset_password(fixture.user_id, %{"password" => "Reset!456"},
              authorization: %{
                principal: %{
                  user_id: fixture.user_id,
                  permissions: ["permission:manage", "user:reset-password"]
                },
                permission: "user:reset-password"
              }
            )
          end)

        send(test_pid, {reset_ref, result})
      end)

    assert :ok = await_advisory_waiters(2, System.monotonic_time(:millisecond) + 15_000)

    release_lock_holder(lock_holder)

    reset_result = await_result(elem(reset_task, 0), elem(reset_task, 1), reset_ref)
    refresh_result = await_result(elem(refresh_task, 0), elem(refresh_task, 1), refresh_ref)

    assert {:ok, %{password: _password}} = reset_result

    case refresh_result do
      {:error, :invalid_refresh_token} ->
        :ok

      {:ok, refreshed_tokens} ->
        assert {:error, :invalid_token} = Auth.authenticate_access_token(refreshed_tokens.token)

      other ->
        flunk("unexpected refresh result: #{inspect(other)}")
    end

    refute with_unboxed(fn -> Auth.Session.active?(fixture.user_id, fixture.jti) end)

    assert [] =
             with_unboxed(fn ->
               Auth.Session.list_active()
               |> then(fn {:ok, sessions} ->
                 Enum.filter(sessions, &(&1.user_id == fixture.user_id))
               end)
             end)
  end

  test "password reset prevents a waiting login from using the old password" do
    fixture = create_fixture()
    lock_holder = hold_user_lock(fixture.user_id)

    on_exit(fn ->
      release_lock_holder(lock_holder)
      await_task(lock_holder)

      with_unboxed(fn ->
        Repo.delete_all(
          from(session in KeystonePhoenix.Auth.AuthSession,
            where: session.user_id == ^fixture.user_id
          )
        )

        Repo.delete_all(from(user in SysUser, where: user.user_id == ^fixture.user_id))
      end)
    end)

    test_pid = self()
    reset_ref = make_ref()

    reset_task =
      spawn_monitor(fn ->
        result =
          with_unboxed(fn ->
            User.reset_password(fixture.user_id, %{"password" => "Reset!456"},
              authorization: %{
                principal: %{
                  user_id: fixture.user_id,
                  permissions: ["permission:manage", "user:reset-password"]
                },
                permission: "user:reset-password"
              }
            )
          end)

        send(test_pid, {reset_ref, result})
      end)

    assert :ok = await_advisory_waiters(1, System.monotonic_time(:millisecond) + 15_000)

    login_ref = make_ref()

    login_task =
      spawn_monitor(fn ->
        result =
          with_unboxed(fn ->
            Auth.login_plaintext(fixture.username, "Strong!123")
          end)

        send(test_pid, {login_ref, result})
      end)

    assert :ok = await_advisory_waiters(2, System.monotonic_time(:millisecond) + 15_000)
    release_lock_holder(lock_holder)

    assert {:ok, _user} = await_result(elem(reset_task, 0), elem(reset_task, 1), reset_ref)

    assert {:error, :invalid_credentials} =
             await_result(elem(login_task, 0), elem(login_task, 1), login_ref)

    refute with_unboxed(fn -> Auth.Session.active?(fixture.user_id, fixture.jti) end)

    assert [] =
             with_unboxed(fn ->
               Auth.Session.list_active()
               |> then(fn {:ok, sessions} ->
                 Enum.filter(sessions, &(&1.user_id == fixture.user_id))
               end)
             end)
  end

  defp await_task({pid, monitor_ref}) do
    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
    after
      1_000 ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
        after
          1_000 -> :ok
        end
    end
  end

  defp hold_user_lock(user_id) do
    test_pid = self()

    spawn_monitor(fn ->
      with_unboxed(fn ->
        Repo.transaction(fn ->
          Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [user_id])
          send(test_pid, {:user_lock_held, self()})

          receive do
            :release -> :ok
          after
            10_000 -> Repo.rollback(:lock_timeout)
          end
        end)
      end)
    end)
    |> then(fn lock_holder ->
      assert_receive {:user_lock_held, _locker_pid}, 5_000
      lock_holder
    end)
  end

  defp release_lock_holder({pid, _monitor_ref}) do
    if Process.alive?(pid), do: send(pid, :release)
  end

  defp create_fixture do
    with_unboxed(fn ->
      user =
        %SysUser{}
        |> SysUser.create_changeset(%{
          username: "refresh_race_#{System.unique_integer([:positive])}",
          password: "Strong!123",
          status: 1
        })
        |> Repo.insert!()

      {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")

      {:ok, claims} =
        KeystonePhoenix.Auth.Token.verify(
          tokens.refresh_token,
          KeystonePhoenix.Auth.Token.refresh_type()
        )

      %{
        user_id: user.user_id,
        username: user.username,
        jti: claims["jti"],
        refresh_token: tokens.refresh_token
      }
    end)
  end

  defp hold_refresh_row(jti) do
    test_pid = self()
    {:ok, jti_bytes} = Ecto.UUID.dump(jti)

    spawn_monitor(fn ->
      with_unboxed(fn ->
        Repo.transaction(fn ->
          Repo.query!("SELECT id FROM auth_sessions WHERE jti = $1 FOR UPDATE", [jti_bytes])
          send(test_pid, {:refresh_row_locked, self()})

          receive do
            :release -> :ok
          after
            10_000 -> Repo.rollback(:lock_timeout)
          end
        end)
      end)
    end)
  end

  defp await_refresh_waiters(deadline) do
    result =
      with_unboxed(fn ->
        Repo.query!("""
        SELECT
          count(*) FILTER (
            WHERE query ILIKE '%auth_sessions%'
              AND wait_event_type = 'Lock'
              AND wait_event IN ('transactionid', 'tuple')
          ),
          count(*) FILTER (
            WHERE query ILIKE '%pg_advisory_xact_lock%'
              AND wait_event_type = 'Lock'
              AND wait_event = 'advisory'
          )
        FROM pg_stat_activity
        WHERE datname = current_database()
          AND pid <> pg_backend_pid()
        """)
      end)

    case {result.rows, System.monotonic_time(:millisecond) < deadline} do
      {[[row_waiters, advisory_waiters]], _remaining?}
      when row_waiters + advisory_waiters == 2 ->
        :ok

      {_, true} ->
        Process.sleep(10)
        await_refresh_waiters(deadline)

      _ ->
        {:error, :waiter_count_mismatch}
    end
  end

  defp await_advisory_waiters(expected, deadline) do
    count =
      with_unboxed(fn ->
        Repo.query!("""
        SELECT count(*)
        FROM pg_stat_activity
        WHERE datname = current_database()
          AND pid <> pg_backend_pid()
          AND query ILIKE '%pg_advisory_xact_lock%'
          AND wait_event_type = 'Lock'
          AND wait_event = 'advisory'
        """)
      end)
      |> Map.fetch!(:rows)
      |> hd()
      |> hd()

    cond do
      count == expected ->
        :ok

      System.monotonic_time(:millisecond) < deadline ->
        Process.sleep(10)
        await_advisory_waiters(expected, deadline)

      true ->
        {:error, {:waiter_count_mismatch, expected, count}}
    end
  end

  defp with_unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  defp await_result(pid, monitor_ref, result_ref) do
    receive do
      {^result_ref, result} ->
        receive do
          {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> result
        after
          1_000 -> :task_exit_timeout
        end

      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        :task_failed
    after
      10_000 ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :timeout
        after
          1_000 -> :task_cleanup_timeout
        end
    end
  end

  defp classify_result({:ok, _tokens}), do: :ok
  defp classify_result({:error, reason}), do: {:error, reason}
  defp classify_result(_other), do: :unexpected
end
