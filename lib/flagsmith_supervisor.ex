defmodule Flagsmith.Supervisor do
  use Supervisor
  require Logger

  def child_spec(_),
    do: %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :supervisor
    }

  def start_link() do
    Logger.info("::: ::: Starting General Flagsmith Supervisor: #{__MODULE__} ::: :::")
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init([]) do
    children = [
      {Registry, [keys: :unique, name: Flagsmith.Registry]},
      Flagsmith.Client.Analytics.Processor.Supervisor,
      Flagsmith.Client.Poller.Supervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
