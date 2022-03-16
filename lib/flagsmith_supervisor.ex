defmodule Flagsmith.Supervisor do
  use Supervisor
  require Logger

  @moduledoc """
  Implements the necessary supervision tree to ensure Poller and Analytics processors
  can be started, accessed and supervised correctly.

  This supervisor starts 3 additional processes, a local `Registry` and two dynamic
  supervisors responsible for starting Pollers and Analytics processes (usually
  a single one, but since they are isolated by sdk key used, if you use multiple
  sdks to access different environments in Flagsmith, in the same application you'll
  end up with that same amount of processes, number of environments times 2).
  The pollers and analytics are only started once there are interactions with either,
  and they stay until application shutdown.
  """

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

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
