defmodule Redex do
  @moduledoc """
  Documentation for `Redex`.
  """
  @type action() :: {atom(), any()}

  @type option :: {:context, map()} | {:timeout, non_neg_integer()}

  @type store_pid :: pid()

  @doc """
  Launch a new store under the store supervisor.
  """
  @spec start_store(module(), String.t(), [{:context, map} | {:timeout, non_neg_integer}]) ::
          Redex.StoreSupervisor.on_start_store()
  def start_store(store, id, opts \\ []) do
    Redex.StoreSupervisor.start_store(store, id, opts)
  end

  @spec dispatch(store :: store_pid(), action :: action()) :: :ok
  def dispatch(store, action) do
    Redex.Store.dispatch(store, action)
  end


end
