defmodule KeystonePhoenixWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  alias KeystonePhoenix.Auth.Session
  alias KeystonePhoenix.Cache
  alias KeystonePhoenix.RuntimeStore

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://telemetry-metrics.hexdocs.pm
      {:telemetry_poller, measurements: periodic_measurements(), period: telemetry_period()}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

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
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      {__MODULE__, :measure_runtime, []}
    ]
  end

  defp telemetry_period do
    Application.get_env(:keystone_phoenix, :telemetry_period_ms, 10_000)
    |> max(1_000)
  end
end
