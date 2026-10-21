defmodule SpecAdapter.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT", "8080"))

    children = [
      %{
        id: SpecAdapter.Clients,
        start:
          {Agent, :start_link,
           [fn -> %{next_id: 1, clients: %{}} end, [name: SpecAdapter.Clients]]}
      },
      {Bandit, plug: SpecAdapter, port: port}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
