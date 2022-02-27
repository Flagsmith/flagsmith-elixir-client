defmodule Flagsmith.Client.Analytics.Processor do
  require Logger

  alias Flagsmith.Schemas

  @behaviour :gen_statem

  # in milliseconds
  @default_cycle 60_000

  @enforce_keys [:client]
  defstruct [:client, :refresh_cycle, tracking: %{}]

  @doc """
  Returns the default child specification for the statem
  """
  def child_spec(args),
    do: %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      type: :worker
    }

  #################################
  ########### API
  #################################

  def track(%Schemas.Features.FeatureState{feature: %{id: id}}),
    do: :gen_statem.cast(__MODULE__, {:track, id})

  def track(%Schemas.Features.Feature{id: id}),
    do: :gen_statem.cast(__MODULE__, {:track, id})

  def track(_),
    do: {:error, :invalid_feature}

  @spec start_link() :: {:ok, pid()} | {:error, term()}
  @spec start_link(opts :: Keyword.t() | nil) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []),
    do:
      :gen_statem.start_link(
        {:local, __MODULE__},
        __MODULE__,
        opts,
        []
      )

  #################################
  ########### Statem Implementation / Internal 
  #################################

  @impl :gen_statem
  def callback_mode(), do: :handle_event_function

  @impl :gen_statem
  def init(options) do
    with client <- Flagsmith.Client.new(options),
         refresh_timeout <- Keyword.get(options, :refresh_cycle, @default_cycle),
         data <- %__MODULE__{client: client, refresh_cycle: refresh_timeout} do
      {:ok, :running, data, [{:next_event, :internal, :dump}]}
    end
  end

  @impl :gen_statem
  def handle_event(:internal, :dump, _, %{tracking: tracking, refresh_cycle: refresh_timeout})
      when map_size(tracking),
      do: {:keep_state_and_data, [{{:timeout, :dump}, refresh_timeout, nil}]}

  def handle_event(
        :internal,
        :dump,
        _,
        %{client: client, tracking: tracking, refresh_cycle: refresh_timeout} = data
      ) do
    case Flagsmith.Client.analytics_track(client, tracking) do
      {:ok, _} ->
        {:keep_state, clean_data(data), [{{:timeout, :dump}, refresh_timeout, nil}]}

      {:error, _} ->
        {:keep_state_and_data, [{{:timeout, :dump}, refresh_timeout, nil}]}
    end
  end

  def handle_event({:timeout, :dump}, nil, _, _data),
    do: {:keep_state_and_data, [{:next_event, :internal, :dump}]}

  def handle_event(:cast, {:track, feature_id}, _, %{tracking: tracking} = data) do
    new_tracking = Map.update(tracking, feature_id, 1, &(&1 + 1))
    {:keep_state, %{data | tracking: new_tracking}, []}
  end

  defp clean_data(%__MODULE__{} = data),
    do: %{data | tracking: %{}}
end
