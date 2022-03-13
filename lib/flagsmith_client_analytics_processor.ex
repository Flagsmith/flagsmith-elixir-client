defmodule Flagsmith.Client.Analytics.Processor do
  require Logger

  alias Flagsmith.Configuration
  alias Flagsmith.Schemas

  @behaviour :gen_statem

  @type processor_identifier :: {__MODULE__, String.t()}
  @type environment_key :: String.t()
  @type identity_id :: String.t() | non_neg_integer()
  @type feature_type ::
          Schemas.Features.FeatureState.t() | Schemas.Features.Feature.t() | Schemas.Flag.t()
  @type env_or_config :: Schemas.Environment.t() | Configuration.t()

  @default_dump_cycle_in_milliseconds 60_000

  @enforce_keys [:configuration]
  defstruct [
    :configuration,
    dump: @default_dump_cycle_in_milliseconds,
    tracking: %{}
  ]

  #################################
  ########### API
  #################################

  @doc """
  Given a `t:Flagsmith.Schemas.Features.FeatureState.t` or 
  `t:Flagsmith.Schemas.Features.Feature.t` or `t:Flagsmith.Schemas.Flag.t` and an
  `t:Flagsmith.Schemas.Environment.t` or `t:Flagsmith.Configuration.t` add or
  increment the call count for feature id to be reported to the analytics endpoint.
  If `:enable_analytics` in the configuration value of the environment isn't true
  it's a no op and returns (:noop), otherwise if   the feature/flag doesn't have an
  id it returns an error.

  Otheriwse it automatically starts a process for the given environment key in case
  one is not running.

  It's a non-blocking operation.
  """
  @spec track(feature_type(), env_or_config()) ::
          :ok | :noop | {:error, {:invalid_feature, term()}}
  def track(
        to_track,
        %Schemas.Environment{
          __configuration__: %Configuration{enable_analytics: true} = config
        }
      ),
      do: track(to_track, config)

  def track(
        to_track,
        %Configuration{enable_analytics: true} = config
      ) do
    case extract_feature_id(to_track) do
      id when is_binary(id) or is_integer(id) ->
        do_track(id, config)

      _ ->
        {:error, {:invalid_feature, to_track}}
    end
  end

  def track(_, _), do: :noop

  defp extract_feature_id(feature) do
    case feature do
      %Schemas.Features.FeatureState{feature: %{id: id}} -> id
      %Schemas.Features.Feature{id: id} -> id
      %Schemas.Flag{feature_id: id} -> id
      _ -> :invalid_feature
    end
  end

  defp do_track(id, %Configuration{environment_key: env_key} = config) do
    case whereis(env_key) do
      pid when is_pid(pid) ->
        :gen_statem.cast(pid, {:track, id})

      :undefined ->
        case __MODULE__.Supervisor.start_child(config) do
          {:ok, pid} -> :gen_statem.cast(pid, {:track, id})
          error -> error
        end
    end
  end

  @doc false
  @spec statem_id(environment_key()) :: processor_identifier()
  def statem_id(environment_key), do: {__MODULE__, environment_key}

  @doc false
  @spec via_tuple(environment_key()) ::
          {:via, Registry, {Flagsmith.Registry, processor_identifier()}}
  def via_tuple(environment_key),
    do: {:via, Registry, {Flagsmith.Registry, statem_id(environment_key)}}

  @doc """
  Returns the pid of Analytics.Processor process related to a given environment key,
  or :undefined if one can't be found.
  """
  @spec whereis(environment_key()) :: :undefined | pid
  def whereis(environment_key) do
    case Registry.lookup(Flagsmith.Registry, statem_id(environment_key)) do
      [] -> :undefined
      [{pid, _}] -> pid
    end
  end

  @doc """
  Starts and links a gen_server represented by this module, using a 
  `t:Flagsmith.Configuration.t` as the basis to derive its registration name and
  inner details.
  """
  @spec start_link(Configuration.t()) :: {:ok, pid()}
  def start_link(%Configuration{environment_key: environment_key} = config) do
    name = via_tuple(environment_key)

    case :gen_statem.start_link(name, __MODULE__, config, []) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Process.link(pid)
        {:ok, pid}

      error ->
        error
    end
  end

  #################################
  ########### Statem Implementation / Internal 
  #################################

  @doc false
  @impl :gen_statem
  def callback_mode(), do: :handle_event_function

  @doc false
  @impl :gen_statem
  def init(%Configuration{} = config),
    do: {:ok, :on, %__MODULE__{configuration: config}, [{:next_event, :internal, :dump}]}

  @doc false
  @impl :gen_statem
  # handle to update the dump time rate. While this might be used in normal situations
  # it's here mostly so while on tests we can start the processor regularly
  # with a configuration and then have it dump way earlier so we can assert the
  # behaviour
  #
  # Here we also set replace the timeout timer, forcing it to be re-evaluated with
  # the new timeout
  def handle_event({:call, from}, {:update_dump_rate, dump_timeout}, _, data),
    do: {
      :keep_state,
      %{data | dump: dump_timeout},
      [{:reply, from, :ok}, {{:timeout, :dump}, dump_timeout, nil}]
    }

  # if the map_size of tracking is 0 then we don't have any item to track
  # and as such we simply set a timer for a new dump
  def handle_event(:internal, :dump, _, %{tracking: tracking, dump: dump_timeout})
      when map_size(tracking) == 0,
      do: {:keep_state_and_data, [{{:timeout, :dump}, dump_timeout, nil}]}

  # on the other hand, if we do have items to track we do call analytics track
  # If all is ok, we can start fresh for new trackings, otherwise we keep the same
  # map as was. In any case we set a new timeout timer for dumping.
  #
  # Notice that while this is synch and runs in the process (so the processor for
  # this particular configuration is blocked while doing the analytics request,
  # this process works around casts, that are async by nature and don't require
  # a response, so the caller that does the cast for tracking a feature doesn't block
  # even if the processor is currently dumping a tracking map
  #
  # There could be a case for making it totally async, but it should only be a problem
  # when talking about hundreds of thousands of tracking requests in burst of 5
  # seconds or so (and even then might not be a problem) so I will say that for now
  # this is quite appropriate.
  def handle_event(
        :internal,
        :dump,
        _,
        %{configuration: config, tracking: tracking, dump: dump_timeout} = data
      ) do
    case Flagsmith.Client.analytics_track(config, tracking) do
      {:ok, _} ->
        {:keep_state, clean_data(data), [{{:timeout, :dump}, dump_timeout, nil}]}

      {:error, _} ->
        {:keep_state_and_data, [{{:timeout, :dump}, dump_timeout, nil}]}
    end
  end

  # when the `:dump` timeout fires, we just move to the dump handle
  def handle_event({:timeout, :dump}, nil, _, _data),
    do: {:keep_state_and_data, [{:next_event, :internal, :dump}]}

  # a cast for tracking a feature_id simply sets or updates that feature id track
  # in the tracking map
  def handle_event(:cast, {:track, feature_id}, _, %{tracking: tracking} = data) do
    new_tracking = Map.update(tracking, feature_id, 1, &(&1 + 1))
    {:keep_state, %{data | tracking: new_tracking}, []}
  end

  # right now just a helper to reset the tracking map
  defp clean_data(%__MODULE__{} = data),
    do: %{data | tracking: %{}}
end
