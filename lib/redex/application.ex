defmodule Redex.Application do
  use Application

  # @dynamic_name Redex.StoreSupervisor
  # @super_name Redex.Supervisor

  # TODO: just launch a dynamic super as the application... one less process
  def start(_type, _args) do
    # children = [
    #   {DynamicSupervisor, name: @dynamic_name, strategy: :one_for_one},
    # ]


    # DynamicSupervisor.start_link()
    # Supervisor.start_link(children, name: @super_name, strategy: :one_for_one)

    Redex.StoreSupervisor.start_link(:ok)
  end

  # def start_child(store, id, context \\ %{}) do
  #   spec = {store, [id,  context]}
  #   Redex.DynamicSupervisor.start_child(spec)
  # end
end
