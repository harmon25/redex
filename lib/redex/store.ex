defmodule Redex.Store do
  @moduledoc """
  Redex store GenServer Behaviour.

  Includes a genserver linked to a dynamic_supervisor monitoring the reducer processes
  """
  def default_callback(old, new, _context) do
    IO.inspect(old, label: "old state")
    IO.inspect(new, label: "new state")
  end

  @doc """
  Link a process to the store - the store will recieve :DOWN messages.

  Store can be launched with a timeout - if there are no links after timeout - the store terminates.
  """
  def link(store_pid, to_monitor_pid) do
    GenServer.cast(store_pid, {:add_link, to_monitor_pid})
  end

  @doc """
  Dispatch an action against the store.
  Acion gets sent to each reducer. If no matching callback is defined - reducer will ignore the action and not modify its' state.
  """
  @spec dispatch(atom | pid | {atom, any} | {:via, atom, any}, any) :: :ok
  def dispatch(pid, action) do
    GenServer.cast(pid, {:dispatch, action})
  end

  @doc """
  Update a store context.

  (consider doing shallow merge?)
  """
  @spec update_context(atom | pid | {atom, any} | {:via, atom, any}, any) :: :ok
  def update_context(pid, new_context) do
    GenServer.cast(pid, {:update_context, new_context})
  end

  @doc """
  Retrieves the current context applied to a context.
  """
  @spec get_context(atom | pid | {atom, any} | {:via, atom, any}) :: map()
  def get_context(pid) do
    GenServer.call(pid, :get_context)
  end

  @doc """
  Retrieves the current state of a store.
  """
  @spec get_state(atom | pid | {atom, any} | {:via, atom, any}) :: any
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @root_reducer opts[:root_reducer]
      @change_callback opts[:change_callback] || {LiveData.Store, :default_callback}

      require Logger
      use GenServer

      @type store_state :: map()

      def start_link([id, context]) do
        name = Module.concat([__MODULE__, "#{id}"])
        GenServer.start_link(__MODULE__, [name, id, context], name: {:global, name})
      end

      @impl GenServer
      def init([name, id, context]) do
        {:ok, root_pid} = @root_reducer.start_link([id, context])

        {:ok,
         %{
           root_pid: root_pid,
           id: id,
           name: name,
           context: context,
           links: []
         }}
      end

      @impl GenServer
      def handle_cast({:add_link, pid}, state) do
        ref = Process.monitor(pid)
        {:noreply, %{state | links: [{ref, pid} | state.links]}}
      end

      @impl GenServer
      def handle_cast({:update_context, context_map}, state) do
        new_context = Map.merge(state.context, context_map)
        {:noreply, %{state | context: new_context}}
      end

      @impl GenServer
      def handle_cast(
            {:dispatch, action},
            %{context: context} = state
          ) do
        child_reducers = Redex.AggReducer.get_child_reducers(state.root_pid)

        old_state = do_get_state(child_reducers)

        # enumerate the root reducers, apply reduction if its a leaf, dispatch to the next branch otherwise
        child_reducers
        |> Enum.each(fn
          {_k, {mod, :reducer, pid}} ->
            Redex.Reducer.reduce(pid, mod, action, context)

          {_k, {mod, :agg, pid}} ->
            Redex.Store.dispatch(pid, action)
        end)

        new_state = do_get_state(child_reducers)
        # run the change callback.
        {m, f} = @change_callback
        apply(m, f, [old_state, new_state, context])
        # @change_callback(old_state, new_state, context)

        {:noreply, state}
      end

      @impl GenServer
      def handle_call(:get_state, _from, state) do
        current_state = Redex.AggReducer.get_child_reducers(state.root_pid) |> do_get_state()
        {:reply, current_state, state}
      end

      @impl GenServer
      def handle_call(:get_context, _from, state) do
        {:reply, state.context, state}
      end

      @impl GenServer
      def handle_info({:DOWN, ref, :process, object, reason}, state) do
        IO.inspect(ref, label: "PROCESS DOWN!")
        IO.inspect(object)
        {:noreply, state}
      end

      @impl GenServer
      def terminate(reason, %{id: id}) do
        require Logger
        Logger.debug("Shutting down #{id} with reason #{inspect(reason)}")
        :ok
      end

      defp do_get_state(reducers) do
        reducers
        |> Enum.reduce(%{}, fn
          {k, {_mod, :agg, pid}}, acc ->
            acc
            |> Map.merge(%{k => do_get_state(Redex.AggReducer.get_child_reducers(pid))})

          {k, {mod, :reducer, pid}}, acc ->
            acc
            |> Map.merge(%{k => apply(Module.concat([mod, State]), :value, [pid])})
        end)
      end
    end
  end
end
