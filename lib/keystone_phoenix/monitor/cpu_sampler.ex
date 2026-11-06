defmodule KeystonePhoenix.Monitor.CpuSampler do
  @moduledoc "Periodic CPU sampler used by the monitoring endpoint."

  use GenServer

  @default_interval_ms 1_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec snapshot() :: map()
  def snapshot do
    GenServer.call(__MODULE__, :snapshot, 1_000)
  rescue
    _error -> zero_cpu(cpu_count())
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, configured_interval())
    schedule(interval)
    {:ok, %{ticks: read_ticks(), info: zero_cpu(cpu_count()), interval_ms: interval}}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.info, state}

  @impl true
  def handle_info(:sample, state) do
    current = read_ticks()
    info = calculate(state.ticks, current, cpu_count())
    schedule(state.interval_ms)
    {:noreply, %{state | ticks: current, info: info}}
  end

  defp calculate(nil, _current, cpu_num), do: zero_cpu(cpu_num)
  defp calculate(_previous, nil, cpu_num), do: zero_cpu(cpu_num)

  defp calculate(previous, current, cpu_num) do
    [user, _nice, system, idle, wait, irq, soft_irq, steal] = pad(current)

    [
      first_user,
      _first_nice,
      first_system,
      first_idle,
      first_wait,
      first_irq,
      first_soft_irq,
      first_steal
    ] = pad(previous)

    user = user - first_user
    system = system - first_system
    idle = idle - first_idle
    wait = wait - first_wait

    total =
      user + system + idle + wait + (irq - first_irq) + (soft_irq - first_soft_irq) +
        (steal - first_steal)

    %{
      "cpuNum" => cpu_num,
      "total" => percent(total, total),
      "sys" => percent(system, total),
      "used" => percent(user, total),
      "wait" => percent(wait, total),
      "free" => percent(idle, total)
    }
  end

  defp read_ticks do
    with {:ok, content} <- File.read("/proc/stat"),
         line when is_binary(line) <-
           Enum.find(String.split(content, "\n"), &String.starts_with?(&1, "cpu ")) do
      line |> String.split() |> Enum.drop(1) |> Enum.map(&parse_integer/1)
    else
      _ -> nil
    end
  end

  defp pad(values), do: Enum.take(values ++ List.duplicate(0, 8), 8)

  defp zero_cpu(cpu_num),
    do: %{
      "cpuNum" => cpu_num,
      "total" => 0.0,
      "sys" => 0.0,
      "used" => 0.0,
      "wait" => 0.0,
      "free" => 0.0
    }

  defp percent(_value, 0), do: 0.0
  defp percent(value, total), do: Float.round(value * 100 / total, 2)

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, _rest} -> integer
      _ -> 0
    end
  end

  defp cpu_count, do: :erlang.system_info(:logical_processors_available) || 1

  defp configured_interval do
    Application.get_env(:keystone_phoenix, :monitor_snapshot_interval_ms, @default_interval_ms)
  end

  defp schedule(interval), do: Process.send_after(self(), :sample, max(interval, 250))
end
