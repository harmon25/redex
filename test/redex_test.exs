defmodule RedexTest do
  use ExUnit.Case
  # doctest Redex

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
      combine_reducers: %{counter: RedexTest.CounterReducer}
  end

  defmodule NestedReducer do
    use Redex.AggReducer,
      combine_reducers: %{counter: RedexTest.CounterReducer, deeply_nested: DeeplyNestedReducer}
  end

  defmodule RootReducer do
    use Redex.AggReducer,
      combine_reducers: %{
        counter: RedexTest.CounterReducer,
        counter2: RedexTest.CounterReducer,
        counter3: RedexTest.CounterReducer
      }
  end

  defmodule NestedRootReducer do
    @moduledoc """
    Sample nested reducer
    """
    use Redex.AggReducer,
      combine_reducers: %{counter: RedexTest.CounterReducer, nested: NestedReducer}
  end

  defmodule NestedStore do
    @moduledoc """
    Sample store with some nested reducers
    """

    use Redex.Store,
      root_reducer: RedexTest.NestedRootReducer,
      change_callback: {RedexTest.NestedStore, :change_callback}

    def change_callback(old_state, new_state, store_context) do
      # do whatever you want after an action has been dispatched, like broadcast diffs
      # diff = Diff.run(old_state, new_state)
      # broadcast!(store_context.socket, %{diff: diff})
    end
  end

  defmodule Store do
    @moduledoc """
    Sample simple store
    """

    use Redex.Store,
      root_reducer: RedexTest.RootReducer,
      change_callback: {RedexTest.Store, :change_callback}

    def change_callback(old_state, new_state, store_context) do
      # do whatever you want after an action has been dispatched, like broadcast diffs
      # diff = Diff.run(old_state, new_state)
      # broadcast!(store_context.socket, %{diff: diff})
    end
  end

  setup_all do
    {:ok, store_pid} = Redex.start_store(__MODULE__.Store, 1)
    {:ok, nested_store_pid} = Redex.start_store(__MODULE__.NestedStore, 2)
    [store: store_pid, nested_store: nested_store_pid]
  end

  test "we have a store!", %{store: store} do
    assert Redex.Store.get_state(store) === %{counter: 0, counter2: 0, counter3: 0}
  end

  test "we have a nested store!", %{nested_store: store} do
    assert Redex.Store.get_state(store) === %{
             counter: 0,
             nested: %{counter: 0, deeply_nested: %{counter: 0}}
           }

    Redex.Store.dispatch(store, {:add, 5})

    assert Redex.Store.get_state(store) === %{
             counter: 5,
             nested: %{counter: 5, deeply_nested: %{counter: 5}}
           }
  end
end
