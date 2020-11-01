defmodule Redex.StoreSupervisor do
  # Automatically defines child_spec/1
  use DynamicSupervisor

  @type option :: {:context, map()} | {:timeout, non_neg_integer()}
  @type on_start_store :: DynamicSupervisor.on_start_child()

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec start_store(store :: module(), id :: String.t(), opts :: [option]) :: on_start_store()
  def start_store(store, id, opts \\ []) do
    DynamicSupervisor.start_child(__MODULE__, {store, [id, opts]})
  end
end
