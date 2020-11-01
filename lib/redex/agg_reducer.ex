defmodule Redex.AggReducer do
  @moduledoc """
  # Aggregate Reducer

  Aggregates the state of sub reducers into a map.

  Must be used at root of the state tree.
  """

  @spec get_child_reducers(atom | pid | {atom, any} | {:via, atom, any}) :: any
  def get_child_reducers(pid) do
    GenServer.call(pid, :__child_reducers)
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @combine_reducers opts[:combine_reducers]
      require Logger
      use GenServer

      def type, do: :agg

      def start_link([id, context]) do
        name = Module.concat([__MODULE__, "Server", "#{id}"])

        GenServer.start_link(__MODULE__, ["#{__MODULE__}.Server#{id}", id, context],
          name: {:global, name}
        )
      end

      @impl true
      def init([name, id, context]) do
        init_state = %{
          id: id,
          type: :agg,
          name: name,
          super_pid: nil,
          context: context,
          reducers: nil
        }

        {:ok, init_state, {:continue, Module.concat([__MODULE__, "Super", "#{id}"])}}
      end

      @impl GenServer
      def handle_continue(super_name, state) do
        {:ok, super_pid} =
          DynamicSupervisor.start_link(
            name: {:global, super_name},
            strategy: :one_for_one
          )

        Logger.debug("Starting Agg Reducer Super #{super_name}")

        reducers = start_reducers(super_pid, state)

        {:noreply, %{state | super_pid: super_pid, reducers: reducers}}
      end

      @impl GenServer
      def handle_cast({:dispatch, action}, %{reducers: reducers, context: context} = state) do
        Enum.each(reducers, fn
          {k, {_mod, :agg, reducer_pid}} ->
            # dispatch to agg reducer..
            Redex.dispatch(reducer_pid, action)

          # actually apply reduction to leaf reducer.
          {k, {mod, :reducer, reducer_pid}} ->
            Redex.Reducer.reduce(reducer_pid, mod, action, context)
        end)

        {:noreply, state}
      end

      @impl GenServer
      def handle_call(:__child_reducers, _from, state) do
        {:reply, state.reducers, state}
      end

      def start_reducers(supervisor, state) do
        # map over reducers, to make child specs to launch.
        {mod_map, specs} =
          Enum.reduce(@combine_reducers, {%{}, []}, fn {k, reducer}, {reducer_mod_map, specs} ->
            case reducer.type() do
              :agg ->
                {Map.merge(reducer_mod_map, %{k => {reducer, :agg}}),
                 [%{id: k, start: {reducer, :start_link, [[state.id, state.context]]}} | specs]}

              :reducer ->
                {Map.merge(reducer_mod_map, %{k => {reducer, :reducer}}),
                 [
                   %{id: k, start: {Module.concat([reducer, State]), :start_link, []}}
                   | specs
                 ]}
            end
          end)

        pid_map =
          Enum.map(specs, fn s ->
            {:ok, pid} = DynamicSupervisor.start_child(supervisor, s)
            {s.id, pid}
          end)
          |> Enum.into(%{})

        # merge pids into map...
        Enum.reduce(mod_map, %{}, fn {k, {mod, type}}, acc ->
          Map.put_new(acc, k, {mod, type, pid_map[k]})
        end)
      end
    end
  end
end
