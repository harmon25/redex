defmodule CounterReducer do
  use Redex.Reducer

  def default_state() do
    0
  end

  def action({:add, number}, state, _context) do
    state + number
  end

  def action({:subtract, number}, state, _context) do
    state - number
  end

  def action({:reset, _}, _state, _context) do
    default_state()
  end

  # serialize callback can be used to retrieve rows from db or strip fields.
  # must be serializable as json.
  def serialize(state) do
    state
  end
end

defmodule DeeplyNestedReducer do
  use Redex.AggReducer,
  combine_reducers: %{counter: CounterReducer}
end


defmodule NestedReducer do
  use Redex.AggReducer,
  combine_reducers: %{counter: CounterReducer, deeply:  DeeplyNestedReducer }
end

defmodule RootReducer do
  use Redex.AggReducer,
  combine_reducers: %{counter: CounterReducer, nested: NestedReducer}
end


defmodule Store do
  use Redex.Store, root_reducer: RootReducer,
    change_callback: {Store, :change_callback}


  def change_callback(old_state, new_state, store_context) do
    IO.inspect(old_state, label: "old")
    IO.inspect(new_state, label: "new")
  end
end


# {:ok, super} = Redex.Supervisor.init(:ok)


# {:ok, store_pid} = Redex.start_store(Store, 1)
