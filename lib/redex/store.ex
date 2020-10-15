defmodule Redex.Store do
  @moduledoc """
  Redex store GenServer Behaviour.

  Includes a genserver linked to a dynamic_supervisor monitoring the reducer processes
  """
  def callback(old, new, _context) do
    IO.inspect(old, label: "old state")
    IO.inspect(new, label: "new state")
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @root_reducer opts[:root_reducer]
      @change_callback opts[:change_callback] || {LiveData.Store, :callback}

      require Logger
      use GenServer

      @type store_state :: map()

      def start_link([id, context]) do
        name = Module.concat([__MODULE__, "#{id}"])
        GenServer.start_link(__MODULE__, [name, id, context], name: {:global, name})
      end

      @impl GenServer
      def init([name, id, context]) do
        {:ok,
         %{
           root_pid: nil,
           id: name,
           context: context
         }, {:continue, id}}
      end

      @impl GenServer
      def handle_continue(id, state) do
        Logger.debug("Launched store super")

        # must have a root reducer assigned to store - it is started, which cascades down.
        {:ok, root_pid} = @root_reducer.start_link([id, state.context])

        {:noreply, %{state | root_pid: root_pid}}
      end

      @impl GenServer
      def handle_cast(
            {:dispatch, action},
            %{context: context} = state
          ) do
        child_reducers = GenServer.call(state.root_pid, :__child_reducers)

        old_state = do_get_state(child_reducers)

        # enumerate the root reducers, apply reduction if its a leaf, dispatch to the next branch otherwise
        child_reducers
        |> Enum.each(fn
          {_k, {mod, :reducer, pid}} ->
            Redex.Reducer.reduce(pid, mod, action, context)

          {_k, {mod, :agg, pid}} ->
            GenServer.cast(pid, {:dispatch, action})
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
        current_state = GenServer.call(state.root_pid, :__child_reducers) |> do_get_state()
        {:reply, current_state, state}
      end

      @impl GenServer
      def terminate(reason, %{id: id}) do
        Logger.debug("Shutting down #{id} with reason #{inspect(reason)}")
        :ok
      end

      @doc """
      Initalize the store -
      """
      @spec initalize(atom | pid | port | {atom, atom}, map | nil) :: any
      def initalize(pid, existing_state \\ nil) do
        send(pid, {:__live_data_init__, existing_state})
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
      Grabs the current state the store.
      """
      @spec get_state(atom | pid | {atom, any} | {:via, atom, any}) :: any
      def get_state(pid) do
        GenServer.call(pid, :get_state)
      end

      defp do_get_state(reducers) do
        reducers
        |> Enum.reduce(%{}, fn
          {k, {_mod, :agg, pid}}, acc ->
            Map.merge(acc, %{k => do_get_state(GenServer.call(pid, :__child_reducers))})

          {k, {mod, :reducer, pid}}, acc ->
            Map.merge(acc, %{k => apply(Module.concat([mod, "AgentStore"]), :value, [pid])})
        end)
      end
    end
  end
end
