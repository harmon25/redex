defmodule Redex.Application do
  use Application

  # @dynamic_name Redex.StoreSupervisor
  # @super_name Redex.Supervisor

  def start(_type, _args) do
    Redex.StoreSupervisor.start_link(:ok)
  end
end
