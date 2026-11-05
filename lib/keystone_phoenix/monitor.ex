defmodule KeystonePhoenix.Monitor do
  @moduledoc "Monitoring queries for Redis, the BEAM host, and online sessions."

  alias KeystonePhoenix.Auth.Session
  alias KeystonePhoenix.Department
  alias KeystonePhoenix.User

  @bytes_per_kilobyte 1024
  @bytes_per_megabyte @bytes_per_kilobyte * 1024
  @bytes_per_gigabyte @bytes_per_megabyte * 1024
  @persistent_start_key {__MODULE__, :started_at}

  @doc "Returns Redis INFO fields and command call counts for the cache page."
  def redis_cache_info do
    with {:ok, info} <- redis_command(["INFO"]),
         {:ok, command_info} <- redis_command(["INFO", "commandstats"]),
         {:ok, db_size} <- redis_command(["DBSIZE"]) do
      {:ok,
       %{
         "info" => parse_info(info),
         "dbSize" => db_size,
         "commandStats" => parse_command_stats(command_info)
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  @doc "Returns online refresh sessions joined with local user and department data."
  def online_users(params \\ %{}) do
    with {:ok, sessions} <- Session.list_active() do
      rows =
        sessions
        |> Enum.map(&online_user_to_map/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.filter(&matches_username?(&1, params["username"] || params[:username]))
        |> Enum.filter(&matches_ip?(&1, params["ipAddress"] || params[:ip_address]))
        |> Enum.sort_by(& &1["loginTime"], :desc)

      {:ok, %{total: length(rows), rows: rows}}
    end
  end

  @doc "Revokes one online refresh session."
  def logout_online_user(token_id), do: Session.revoke_token(token_id)

  @doc "Returns host and BEAM runtime metrics in the existing ServerInfo shape."
  @spec server_info() :: {:ok, map()} | {:error, :unavailable}
  def server_info do
    {:ok,
     %{
       "cpuInfo" => cpu_info(),
       "memoryInfo" => memory_info(),
       "jvmInfo" => beam_info(),
       "systemInfo" => system_info(),
       "diskInfos" => disk_infos()
     }}
  rescue
    _error -> {:error, :unavailable}
  end

  @doc "Returns one network status snapshot for the monitoring SSE endpoint."
  def network_status do
    checked_at = DateTime.utc_now() |> DateTime.to_iso8601()

    %{
      "online" => true,
      "status" => "ONLINE",
      "checkedAt" => checked_at,
      "targets" => []
    }
  end

  defp online_user_to_map(%{jti: token_id, user_id: user_id}) do
    with {:ok, user} <- User.get_user(user_id) do
      dept_name =
        case user.dept_id do
          nil ->
            nil

          dept_id ->
            case Department.get_dept(dept_id) do
              {:ok, dept} -> dept.dept_name
              _ -> nil
            end
        end

      %{
        "tokenId" => token_id,
        "deptName" => dept_name,
        "username" => user.username,
        "ipAddress" => user.login_ip || "",
        "loginLocation" => "",
        "browser" => "",
        "operationSystem" => "",
        "loginTime" => datetime_to_milliseconds(user.login_date)
      }
    else
      _ -> nil
    end
  end

  defp matches_username?(_row, value) when value in [nil, ""], do: true
  defp matches_username?(row, value), do: row["username"] == to_string(value)

  defp matches_ip?(_row, value) when value in [nil, ""], do: true
  defp matches_ip?(row, value), do: row["ipAddress"] == to_string(value)

  defp datetime_to_milliseconds(%DateTime{} = datetime),
    do: DateTime.to_unix(datetime, :millisecond)

  defp datetime_to_milliseconds(%NaiveDateTime{} = datetime) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix(:millisecond)
  end

  defp datetime_to_milliseconds(_datetime), do: nil

  defp redis_command(command) do
    Redix.command(KeystonePhoenix.Redis, command)
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp parse_info(info) when is_binary(info) do
    info
    |> String.split(~r/\r?\n/)
    |> Enum.reduce(%{}, fn line, result ->
      case info_entry(line) do
        {key, value} -> Map.put(result, key, value)
        nil -> result
      end
    end)
  end

  defp parse_info(_info), do: %{}

  defp info_entry(line) do
    separator = if String.contains?(line, ":"), do: ":", else: "="

    case String.split(line, separator, parts: 2) do
      [key, value] when key != "" ->
        if String.starts_with?(key, "#"), do: nil, else: {key, value}

      _ ->
        nil
    end
  end

  defp parse_command_stats(info) when is_binary(info) do
    info
    |> String.split(~r/\r?\n/)
    |> Enum.flat_map(fn line ->
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          if key != "" and String.starts_with?(key, "cmdstat_") do
            [%{"name" => String.trim_leading(key, "cmdstat_"), "value" => extract_calls(value)}]
          else
            []
          end

        _ ->
          []
      end
    end)
  end

  defp parse_command_stats(_info), do: []

  defp extract_calls(value) do
    case Regex.run(~r/(?:^|,)calls=([^,]+)/, value, capture: :all_but_first) do
      [calls] -> calls
      _ -> "0"
    end
  end

  defp cpu_info do
    cpu_num = :erlang.system_info(:logical_processors_available) || 1

    case cpu_ticks() do
      {:ok, first} ->
        Process.sleep(50)

        case cpu_ticks() do
          {:ok, second} -> cpu_percentages(cpu_num, first, second)
          _ -> zero_cpu(cpu_num)
        end

      _ ->
        zero_cpu(cpu_num)
    end
  end

  defp cpu_ticks do
    case File.read("/proc/stat") do
      {:ok, content} ->
        case Enum.find(String.split(content, "\n"), &String.starts_with?(&1, "cpu ")) do
          nil ->
            {:error, :unavailable}

          line ->
            values =
              line
              |> String.split()
              |> Enum.drop(1)
              |> Enum.map(&parse_integer/1)

            {:ok, values}
        end

      error ->
        error
    end
  end

  defp cpu_percentages(cpu_num, first, second) do
    [user, _nice, system, idle, wait, irq, soft_irq, steal] = pad_ticks(second, 8)

    [
      first_user,
      _first_nice,
      first_system,
      first_idle,
      first_wait,
      first_irq,
      first_soft_irq,
      first_steal
    ] =
      pad_ticks(first, 8)

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

  defp pad_ticks(values, count), do: Enum.take(values ++ List.duplicate(0, count), count)

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

  defp memory_info do
    values = proc_meminfo()
    total = values["MemTotal"] || 0
    available = values["MemAvailable"] || values["MemFree"] || 0
    used = max(total - available, 0)

    %{
      "total" => gigabytes(total),
      "used" => gigabytes(used),
      "free" => gigabytes(available),
      "usage" => percent(used, total)
    }
  end

  defp proc_meminfo do
    case File.read("/proc/meminfo") do
      {:ok, content} ->
        Enum.reduce(String.split(content, "\n"), %{}, fn line, result ->
          case Regex.run(~r/^([^:]+):\s+(\d+)/, line, capture: :all_but_first) do
            [key, value] -> Map.put(result, key, parse_integer(value) * @bytes_per_kilobyte)
            _ -> result
          end
        end)

      _ ->
        %{}
    end
  end

  defp beam_info do
    total = :erlang.memory(:total)
    max_memory = (proc_meminfo()["MemTotal"] || total) |> max(total)
    free = max(max_memory - total, 0)
    started_at = started_at()
    uptime = max(System.system_time(:second) - started_at, 0)

    %{
      "total" => megabytes(total),
      "max" => megabytes(max_memory),
      "free" => megabytes(free),
      "used" => megabytes(total),
      "usage" => percent(total, max_memory),
      "name" => "BEAM/OTP #{:erlang.system_info(:otp_release)}",
      "version" => System.version(),
      "home" => to_string(:code.root_dir()),
      "startTime" => DateTime.from_unix!(started_at) |> Calendar.strftime("%Y-%m-%d %H:%M:%S"),
      "runTime" => format_uptime(uptime),
      "inputArgs" => Enum.join(System.argv(), " ")
    }
  end

  defp system_info do
    %{
      "computerName" => hostname(),
      "computerIp" => local_ip(),
      "userDir" => File.cwd!(),
      "osName" => os_name(),
      "osArch" => to_string(:erlang.system_info(:system_architecture))
    }
  end

  defp disk_infos do
    case System.cmd("df", ["-kP"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.drop(1)
        |> Enum.flat_map(&parse_disk_line/1)

      _ ->
        []
    end
  rescue
    _error -> []
  end

  defp parse_disk_line(line) do
    case Regex.run(~r/^\S+\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%\s+(.+)$/, line,
           capture: :all_but_first
         ) do
      [total, used, free, usage, mount] ->
        [
          %{
            "dirName" => mount,
            "sysTypeName" => "",
            "typeName" => "",
            "total" => file_size(parse_integer(total) * @bytes_per_kilobyte),
            "free" => file_size(parse_integer(free) * @bytes_per_kilobyte),
            "used" => file_size(parse_integer(used) * @bytes_per_kilobyte),
            "usage" => parse_integer(usage) * 1.0
          }
        ]

      _ ->
        []
    end
  end

  defp hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _ -> "unknown"
    end
  end

  defp local_ip do
    case :inet.getif() do
      {:ok, interfaces} ->
        interfaces
        |> Enum.map(fn {address, _broadcast, _mask} -> address end)
        |> Enum.find_value("127.0.0.1", fn
          {127, 0, 0, 1} -> nil
          {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
          _ -> nil
        end)

      _ ->
        "127.0.0.1"
    end
  end

  defp os_name do
    case :os.type() do
      {family, name} -> "#{family}/#{name}"
      _ -> "unknown"
    end
  end

  defp started_at do
    case :persistent_term.get(@persistent_start_key, nil) do
      nil ->
        value = System.system_time(:second)
        :persistent_term.put(@persistent_start_key, value)
        value

      value ->
        value
    end
  end

  defp parse_integer(value) do
    case Integer.parse(to_string(value)) do
      {number, _} -> number
      _ -> 0
    end
  end

  defp gigabytes(bytes), do: Float.round(bytes / @bytes_per_gigabyte, 2)
  defp megabytes(bytes), do: Float.round(bytes / @bytes_per_megabyte, 2)

  defp file_size(bytes) when bytes >= @bytes_per_gigabyte,
    do: :io_lib.format("~.1f GB", [bytes / @bytes_per_gigabyte]) |> IO.iodata_to_binary()

  defp file_size(bytes) when bytes >= @bytes_per_megabyte,
    do: :io_lib.format("~.1f MB", [bytes / @bytes_per_megabyte]) |> IO.iodata_to_binary()

  defp file_size(bytes),
    do: :io_lib.format("~.1f KB", [bytes / @bytes_per_kilobyte]) |> IO.iodata_to_binary()

  defp format_uptime(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3_600)
    minutes = div(rem(seconds, 3_600), 60)
    remaining = rem(seconds, 60)
    "#{days}d #{hours}h #{minutes}m #{remaining}s"
  end
end
