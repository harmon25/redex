defmodule Redex do
  @moduledoc """
  Documentation for `Redex`.
  """
  @type action() :: {atom(), any()}

  def start_store(store, id, context \\ %{}) do
    Redex.StoreSupervisor.start_child(store, id, context)
  end

  @spec dispatch(pid(), action()) :: :ok
  def dispatch(pid, action) do
    GenServer.cast(pid, {:dispatch, action})
  end

  @spec get_state(pid()) :: any()
  def get_state(store_pid) do
    GenServer.call(store_pid, :get_state)
  end
end
