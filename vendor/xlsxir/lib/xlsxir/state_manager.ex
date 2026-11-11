defmodule Xlsxir.StateManager do
  @moduledoc """
  GenServer to manage ETS table state/<C-y>
  """

  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(init_arg) do
    {:ok, init_arg}
  end

  def handle_call(:new_table, _from, state) do
    {:reply, :ets.new(:table, [:set, :public]), state}
  end
end
