defmodule KeystonePhoenix.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        KeystonePhoenixWeb.Telemetry,
        KeystonePhoenix.RuntimeStore,
        KeystonePhoenix.Monitor.CpuSampler,
        KeystonePhoenix.Repo,
        KeystonePhoenix.Auth.SessionCleanup,
        KeystonePhoenix.Job.Lock,
        {Task.Supervisor,
         name: KeystonePhoenix.JobTaskSupervisor,
         max_children: Application.get_env(:keystone_phoenix, :job_task_max_children, 64)},
        scheduler_child(),
        {DNSCluster,
         query: Application.get_env(:keystone_phoenix, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: KeystonePhoenix.PubSub},
        # Start a worker by calling: KeystonePhoenix.Worker.start_link(arg)
        # {KeystonePhoenix.Worker, arg},
        # Start to serve requests, typically the last entry
        KeystonePhoenixWeb.Endpoint
      ]
      |> List.flatten()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: KeystonePhoenix.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp scheduler_child do
    if Application.get_env(:keystone_phoenix, :job_scheduler_enabled, true) do
      KeystonePhoenix.Job.Scheduler
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KeystonePhoenixWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
