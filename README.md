# Redex

Redux implementation in Elixir for predictable server side state containers. Emulates a redux-like API.

Reducers are composed to create a state graph.
The Store initalizes the reducers, and is the entrypoint for all actions against a particular store.

This is different from frontend redux in that each user gets a server side state store, as apposed to a single redux store in the UI.

There is no coupling to phoenix, or channels. 

A `Store` can be initialized on login/channel join, and interacted with through a session either via channels or some other stateful transport.

## Usage

### Define one or more reducers.

```elixir

# simple counter reducer - default state can be anything 
defmodule MyApp.CounterReducer do
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
```

### Define atleast one AggregateReducer
This requires the `combine_reducers` option as a map which represents the shape of this branch of the state.

```elixir
defmodule MyApp.RootReducer do
  use Redex.AggReducer, 
    combine_reducers: %{counter: MyApp.CounterReducer}
end
```

### Define a store module in your application

The store requires the following options:
- `root_reducer` which must be an aggregate reducer, 
- `change_callback` a 3 arity function taking `old_state`, `new_state` and that particulars stores context as parameters. 

```elixir
defmodule MyApp.Store do
  use Redex.Store, 
    root_reducer: MyApp.RootReducer,
    change_callback: {MyApp.Store, :change_callback}

  def change_callback(old_state, new_state, store_context) do
    # do whatever you want after an action has been dispatched, like broadcast diffs
    diff = Diff.run(old_state, new_state)
    broadcast!(store_context.socket, %{diff: diff})
  end
end
```

```elixir
# start the store with a unique ID, and some context
{:ok, store_pid} = MyApp.Store.start(1, %{user_id: 1, socket: socket})
MyApp.Store.get_state(store_pid)
> %{counter: 0}
MyApp.Store.dispatch(store_pid, {:add, 5})
> :ok
MyApp.Store.get_state(store_pid)
> %{counter: 5}
```

## Testing
Dispatch actions against the initalized store and assert the state is correct.

```elixir
{:ok, store_pid} = MyApp.Store.start(1)
:ok = MyApp.Store.dispatch(store_pid, {:add, 5})
assert MyApp.Store.get_state(store_pid) === %{counter: 5}
```

## TODO

- finish implementation
- middlware? 
  - not sure it is neccessary


## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `redex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:redex, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/redex](https://hexdocs.pm/redex).
