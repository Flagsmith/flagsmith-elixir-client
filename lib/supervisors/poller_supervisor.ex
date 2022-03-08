defmodule Flagsmith.Client.Poller.Supervisor do
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

  @spec start_child(opts :: Keyword.t()) :: {:ok, pid()} | {:error, any()}
  def start_child(opts \\ []) do
    DynamicSupervisor.start_child(
      __MODULE__,
      %{
        id: Flagsmith.Client.Poller,
        start: {Flagsmith.Client.Poller, :start_link, [opts]},
        shutdown: 25_000,
        restart: :temporary,
        type: :worker
      }
    )
  end

  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)
end
