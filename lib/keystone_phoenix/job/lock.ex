defmodule KeystonePhoenix.Job.Lock do
  @moduledoc """
  Coordinates single-node scheduled-job execution locks.

  The owner process is monitored. If the owner is terminated before it releases
  the lock, the monitor removes the lock so a later trigger can run.
  """

  use GenServer

  @doc "Starts the job lock manager."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Attempts to acquire a job lock for the calling process."
  def acquire(job_id) when is_binary(job_id) do
    GenServer.call(__MODULE__, {:acquire, job_id, self()})
  end

  @doc "Releases a job lock owned by the calling process."
  def release(job_id) when is_binary(job_id) do
    GenServer.call(__MODULE__, {:release, job_id, self()})
  end

  @doc "Returns whether a job currently has an execution lock."
  def held?(job_id) when is_binary(job_id) do
    GenServer.call(__MODULE__, {:held?, job_id})
  end

  @impl true
  def init(_opts), do: {:ok, %{locks: %{}, monitors: %{}}}

  @impl true
  def handle_call({:acquire, job_id, owner}, _from, state) do
    case Map.get(state.locks, job_id) do
      nil ->
        ref = Process.monitor(owner)
        lock = %{owner: owner, ref: ref}
        locks = Map.put(state.locks, job_id, lock)
        monitors = Map.put(state.monitors, ref, job_id)
        {:reply, :ok, %{state | locks: locks, monitors: monitors}}

      _lock ->
        {:reply, :busy, state}
    end
  end

  def handle_call({:release, job_id, owner}, _from, state) do
    case Map.get(state.locks, job_id) do
      %{owner: ^owner, ref: ref} ->
        Process.demonitor(ref, [:flush])
        {:reply, :ok, remove_lock(state, job_id, ref)}

      _lock ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:held?, job_id}, _from, state) do
    {:reply, Map.has_key?(state.locks, job_id), state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _owner, _reason}, state) do
    case Map.get(state.monitors, ref) do
      nil ->
        {:noreply, state}

      job_id ->
        {:noreply, remove_lock(state, job_id, ref)}
    end
  end

  defp remove_lock(state, job_id, ref) do
    %{
      state
      | locks: Map.delete(state.locks, job_id),
        monitors: Map.delete(state.monitors, ref)
    }
  end
end
