defmodule Redex.Application do
  use Application

  @dynamic_name Redex.StoreSupervisor
  @super_name Redex.Supervisor

  def start(_type, _args) do
    children = [
      {DynamicSupervisor, name: @dynamic_name, strategy: :one_for_one},
    ]

    Supervisor.start_link(children, name: @super_name, strategy: :one_for_one)
  end

  def start_child(store, id, context \\ %{}) do
    spec = {store, [id,  context]}
    DynamicSupervisor.start_child(@dynamic_name, spec)
  end
end
