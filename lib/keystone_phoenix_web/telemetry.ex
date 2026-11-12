defmodule KeystonePhoenixWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  alias KeystonePhoenix.Auth.Session
  alias KeystonePhoenix.Cache
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.RuntimeStore

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children =
      [
        # Telemetry poller will execute the given period measurements
        # every 10_000ms. Learn more here: https://telemetry-metrics.hexdocs.pm
        {:telemetry_poller, measurements: periodic_measurements(), period: telemetry_period()},
        console_reporter_child()
      ]
      |> List.flatten()

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("keystone_phoenix.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("keystone_phoenix.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("keystone_phoenix.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("keystone_phoenix.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("keystone_phoenix.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Keystone runtime metrics
      last_value("keystone_phoenix.runtime.cache_entries"),
      last_value("keystone_phoenix.runtime.captcha_entries"),
      last_value("keystone_phoenix.runtime.auth_sessions"),
      last_value("keystone_phoenix.repo.pool.ready_connections"),
      last_value("keystone_phoenix.repo.pool.checkout_queue_length"),
      last_value("keystone_phoenix.repo.pool.pool_size"),
      last_value("keystone_phoenix.repo.pool.pool_count"),
      counter("keystone_phoenix.repo.pool.alert.count", tags: [:reason]),
      counter("keystone_phoenix.authz.decision.count", tags: [:outcome]),
      summary("keystone_phoenix.job.run.duration",
        tags: [:job_id, :trigger_type, :status],
        unit: {:native, :millisecond}
      )
    ]
  end

  @doc "Emits low-cost runtime gauges for ETS and PostgreSQL-backed sessions."
  def measure_runtime do
    sessions =
      case Session.count_active() do
        {:ok, count} -> count
        _ -> 0
      end

    :telemetry.execute(
      [:keystone_phoenix, :runtime],
      %{
        cache_entries: Cache.stats().entries,
        captcha_entries: :ets.info(RuntimeStore.captcha_table(), :size),
        auth_sessions: sessions
      },
      %{}
    )
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end

  @doc "Emits PostgreSQL connection pool capacity and queue gauges."
  def measure_repo_pool do
    config = Repo.config()
    pool_metrics = pool_metrics()

    measurements = %{
      ready_connections: Enum.sum_by(pool_metrics, & &1.ready_conn_count),
      checkout_queue_length: Enum.sum_by(pool_metrics, & &1.checkout_queue_length),
      pool_size: Keyword.get(config, :pool_size, 0),
      pool_count: Keyword.get(config, :pool_count, 1)
    }

    :telemetry.execute(
      [:keystone_phoenix, :repo, :pool],
      measurements,
      %{}
    )

    maybe_emit_pool_alert(measurements)
    :ok
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      {__MODULE__, :measure_runtime, []},
      {__MODULE__, :measure_repo_pool, []}
    ]
  end

  # 报告组件默认关闭，只在明确配置后输出指标，避免生产环境产生高频日志。
  defp console_reporter_child do
    if Application.get_env(:keystone_phoenix, :telemetry_console_reporter, false) do
      {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    else
      []
    end
  end

  # 通过 Repo 注册表读取实际连接池，避免直接依赖连接池进程名称。
  defp pool_metrics do
    metrics =
      case Ecto.Repo.Registry.lookup(Repo) do
        %{pid: _pid, opts: opts, partition_supervisor: {name, _count}} ->
          pool = Keyword.get(opts, :pool, DBConnection.ConnectionPool)

          name
          |> PartitionSupervisor.which_children()
          |> Enum.flat_map(fn {_id, child_pid, _type, _modules} ->
            safe_pool_metrics(pool, child_pid)
          end)

        %{pid: pid, opts: opts} ->
          pool = Keyword.get(opts, :pool, DBConnection.ConnectionPool)
          safe_pool_metrics(pool, pid)

        _ ->
          []
      end

    case metrics do
      [] -> fallback_pool_metric()
      metrics -> metrics
    end
  end

  defp safe_pool_metrics(pool, pid) do
    pool.get_connection_metrics(pid)
    |> Enum.filter(&is_map/1)
    |> Enum.filter(&valid_pool_metric?/1)
  rescue
    _error -> []
  catch
    :exit, _reason -> []
  end

  # 只发送结构化告警事件，由外部报告组件决定记录、聚合或通知方式。
  defp maybe_emit_pool_alert(%{checkout_queue_length: queue} = measurements) do
    threshold = Application.get_env(:keystone_phoenix, :repo_pool_queue_alert_threshold, 1)

    if is_integer(threshold) and threshold >= 0 and queue >= threshold do
      :telemetry.execute(
        [:keystone_phoenix, :repo, :pool, :alert],
        %{count: 1, checkout_queue_length: queue},
        %{
          reason: :checkout_queue,
          threshold: threshold,
          pool_size: measurements.pool_size,
          pool_count: measurements.pool_count
        }
      )
    end
  end

  defp fallback_pool_metric, do: [%{ready_conn_count: 0, checkout_queue_length: 0}]

  defp valid_pool_metric?(%{ready_conn_count: ready, checkout_queue_length: queue})
       when is_integer(ready) and ready >= 0 and is_integer(queue) and queue >= 0,
       do: true

  defp valid_pool_metric?(_metric), do: false

  defp telemetry_period do
    Application.get_env(:keystone_phoenix, :telemetry_period_ms, 10_000)
    |> max(1_000)
  end
end
