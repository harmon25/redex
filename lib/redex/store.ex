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
       # def callback(old, new, _context) do
       #   IO.inspect(old, label: "old state")
       #   IO.inspect(new, label: "new state")
       # end

       @root_reducer opts[:root_reducer]
       @change_callback opts[:change_callback] || {LiveData.Store, :callback}
       # @root_reducer Keyword.get(unquote(opts), :root_reducer)
       require Logger
       use GenServer

       @type store_state :: map()

       # def child_spec(opts) do
       #   %{
       #     start: {__MODULE__, :start, [opts]},
       #     type: :worker
       #   }
       # end

       def start(
             id,
             context \\ %{}
           ) do
         name = "ld_store_#{id}"

         GenServer.start(__MODULE__, [id, context], name: {:global, name})
         |> case do
           {:ok, pid} ->
             Logger.debug("Launched new #{__MODULE__}: #{name}")
             {:ok, :new, pid}

           {:error, {:already_started, pid}} ->
             Logger.debug("Associated Existing #{__MODULE__}: #{name}")
             {:ok, :existing, pid}
         end
       end

       @impl GenServer
       def init([id, context]) do
         # channel pids is a list - as this user could be connected via different sockets
         {:ok,
          %{
            super_pid: nil,
            id: id,
            channel_pids: [],
            children: [],
            context: context,
          }, {:continue, "ld_store_super_#{id}"}}
       end

       @impl GenServer
       def handle_continue(super_name, state) do
         super_pid =
           DynamicSupervisor.start_link(
             name: {:global, super_name},
             strategy: :one_for_one
           )
           |> case do
             {:ok, pid} ->
               Logger.debug("Launched new #{super_name}")
               pid

             {:error, {:already_started, pid}} ->
               Logger.debug("Associated Existing #{super_name}")
               pid
           end

         {:noreply, %{state | super_pid: super_pid}}
       end

       # should change this into something that reduces the reducers..not into...
         def init_reducer(reducer, old_state) do
         children = reducer.children()
         key = reducer.key()
         default_st = reducer.default_state(old_state)

         if key == :root do
           # root starts as map...
           Enum.into(children, default_st, &init_reducer(&1, old_state))
         else
           case children do
             [] ->
               {key, default_st}
             children ->
               into = case default_st do
                 default_st when is_map(default_st) -> default_st
                 default_st -> Map.new([{key, default_st}])
               end

               Enum.into(children, into, &init_reducer(&1, old_state[&1.key]))

           end
         end
       end

       @impl GenServer
       def handle_info({:__live_data_init__, nil}, %{super_pid: super_pid, context: context} = state) do
         Logger.debug("Init store for #{state.id}!")

         # for now will be statically defining reducer structure in config.exs - but this could be moved into some macro?

         to_launch =
           Application.get_env(:live_data_demo, :reducer)
           |> case do
             nil ->
               # throw "No :reducer configuration in :live_data application env. "
               Logger.error("No :reducer configuration in :live_data application env. stopping... ")
               {:stop, :normal, state}

             reducer ->
               # init the root reducer - and the reduce the results into something useful
               reducer.action({:init, nil}, nil, context)
               |> Enum.reduce([], fn {k, red}, agents ->
                 [{k, red} | agents]
               end)
           end

         children =
           to_launch
           |> Enum.map(fn {k, v} ->
             Logger.info("starting #{k} agent")
             {:ok, pid} = DynamicSupervisor.start_child(super_pid, Module.concat([v, AgentStore]))
             {k, v, pid}
           end)

         dispatch(self(), {:init, nil})
         {:noreply, %{state | children: children}}
       end

       # monitor the channel process - so we know when the connection is lost...
       def handle_info({:__live_data_monitor__, channel_pid}, state) do
         Logger.debug("Monitoring #{inspect(channel_pid)}")
         Process.monitor(channel_pid)
         {:noreply, %{state | channel_pids: [channel_pid | state.channel_pids]}}
       end

       def handle_info({:DOWN, _ref, :process, object, _reason}, state) do
         Logger.debug(label: "Channel process #{inspect(object)} down!")
         Process.send_after(self(), :__live_data_shutdown__, 10000)
         {:noreply, %{state | channel_pids: Enum.reject(state.channel_pids, &(&1 == object))}}
       end

       def handle_info(:__live_data_shutdown__, %{channel_pids: []} = state) do
         # have no associated channel pid after 10 seconds. leave it.
         {:stop, :normal, state}
       end

       def handle_info(:__live_data_shutdown__, state) do
         Logger.debug("Skipping shutdown, new channel associated")
         {:noreply, state}
       end

       @impl GenServer
       def handle_cast(
             {:dispatch, action},
             %{children: children, context: context} = state
           ) do
         # enumerate the child, reducers - and apply this reduction
         # each reducion is executed inside an agent so this should be concurrent.
         old_state = do_get_state(children)

         Enum.each(children, fn {_k, mod, pid} ->
           LiveData.Reducer.reduce(pid, mod, action, context)
         end)

         new_state = do_get_state(children)
         # run the callback.

         {m,f} = @change_callback
         apply(m, f, [old_state, new_state, context])
         # @change_callback(old_state, new_state, context)

         {:noreply, state}
       end

       @impl GenServer
       def handle_call(:get_state, _from, %{children: children} = state) do
         current_state = do_get_state(children)

         {:reply, current_state, state}
       end

       @impl GenServer
       def terminate(reason, %{super_pid: spid, id: id}) do
         Logger.debug("Shutting down #{id} with reason #{inspect(reason)}")
         DynamicSupervisor.stop(spid)
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

       defp do_get_state(children) do
         Enum.into(children, %{}, fn {k, mod, pid} ->
           {k, apply(Module.concat([mod, "AgentStore"]), :value, [pid])}
         end)
       end
     end
   end


 end
