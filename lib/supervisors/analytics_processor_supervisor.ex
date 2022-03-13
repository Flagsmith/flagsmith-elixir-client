defmodule Flagsmith.Client.Analytics.Processor.Supervisor do
  use DynamicSupervisor

  require Logger

  def child_spec(_),
    do: %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :supervisor
    }

  def start_link() do
    Logger.info("::: ::: Starting #{__MODULE__} ::: :::")
    DynamicSupervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @spec start_child(Flagsmith.Configuration.t()) :: {:ok, pid()} | {:error, any()}
  def start_child(%Flagsmith.Configuration{} = config) do
    DynamicSupervisor.start_child(
      __MODULE__,
      %{
        id: Flagsmith.Client.Analytics.Processor,
        start: {Flagsmith.Client.Analytics.Processor, :start_link, [config]},
        shutdown: 25_000,
        restart: :temporary,
        type: :worker
      }
    )
  end

  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)
end
