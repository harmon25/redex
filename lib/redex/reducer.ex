defmodule Redex.Reducer do
  @moduledoc """
 Reducer module

 A reducer is a module that implements action/3 and default_state/1 callbacks.

 action/3 takes an action_arg, current_state store context - and returns a new state.

 Can be used on its own, or combined into a RootReducer.

 This module also implements persistence for the state in the form of an agent which is the context in which the action and default_state callbacks are executed.
 """

 @type reducer_agent :: atom | pid | {atom, any} | {:via, atom, any}
 @type store_context :: map()

 @spec value(reducer_agent) :: any
 def value(pid) do
   Agent.get(pid, & &1)
 end

 @spec reduce(reducer_agent, atom, store_context) :: :ok
 def reduce(pid, module, action, context \\ %{}) do
   Agent.cast(pid, &apply(module, :action, [action, &1, context]))
 end

 defmacro __using__(_opts) do
   quote do
     @parent Module.split(__MODULE__) |> Enum.drop(-1) |> Module.concat()
     @type action :: atom()
     @type store_context :: map()
     @type payload :: map()
     @type action_arg :: {action, payload}
     @type state :: any()
     @type reducer :: module()

     @callback key() :: atom()
     @callback children() :: [module()]
     @callback action(action :: action_arg(), state :: state(), context :: store_context()) ::
                 state()
     @callback serialize(state()) :: state()

     @callback default_state() :: state()
     @callback default_state(existing_state :: state()) :: state()

     @optional_callbacks default_state: 1

     defmodule AgentStore do
       @parent Module.split(__MODULE__) |> Enum.drop(-1) |> Module.concat()

       use Agent

       def start_link([]) do
         Agent.start_link(fn -> @parent.default_state() end)
       end

       def start_link() do
         Agent.start_link(fn -> @parent.default_state() end)
       end

       def start_link(nil) do
         Agent.start_link(fn -> @parent.default_state() end)
       end

       def start_link(initial_value) do
         Agent.start_link(fn -> @parent.default_state(initial_value) end)
       end

       def raw_value(pid) do
         Agent.get(pid, & &1)
       end

       def value(pid) do
         @parent.serialize(raw_value(pid))
       end

       def reduce(pid, action, context \\ %{}) do
         Agent.update(pid, fn state ->
           @parent.action(action, state, context)
         end)
       end
     end

     # injecting these init callbacks - that initialize the default state.
     def action({:init, nil}, state, _) when is_nil(state) do
       default_state()
     end

     def action({:init, nil}, state, _) do
       state
     end

     def action({:init, existing_state}, _, _) do
       existing_state
     end

     def default_state(nil) do
       default_state()
     end

     def default_state(existing_state) do
       existing_state
     end

   end
 end
end
