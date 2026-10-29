defmodule Flagsmith.Client.Events.Processor do
  use GenServer
  require Logger
  @moduledoc false

  alias Flagsmith.Configuration

  @type processor_identifier :: {__MODULE__, String.t()}
  @type environment_key :: String.t()
  @type event :: %{
          required(:event) => String.t(),
          required(:feature_name) => String.t() | nil,
          required(:identifier) => String.t() | nil,
          required(:value) => String.t() | nil,
          required(:traits) => map() | nil,
          required(:metadata) => map(),
          required(:timestamp) => integer()
        }

  @flag_exposure_event "$flag_exposure"
  @max_buffered_events 1000

  @enforce_keys [:configuration]
  defstruct [
    :configuration,
    buffer: [],
    exposure_keys: MapSet.new()
  ]

  #################################
  ########### API
  #################################

  @doc false
  @spec flag_exposure_event() :: String.t()
  def flag_exposure_event(), do: @flag_exposure_event

  @doc """
  Buffers an event to be sent to the Flagsmith events API on the next flush, starting
  a processor for the configuration's environment key in case one is not running.

  Exposures equal in feature, identifier and value to one already buffered are
  dropped, as they add no information.

  It's a non-blocking operation.
  """
  @spec track(event(), Configuration.t()) :: :ok | {:error, term()}
  def track(event, %Configuration{environment_key: env_key} = config) do
    case whereis(env_key) do
      pid when is_pid(pid) ->
        GenServer.cast(pid, {:track, event})

      :undefined ->
        case __MODULE__.Supervisor.start_child(config) do
          {:ok, pid} -> GenServer.cast(pid, {:track, event})
          {:error, {:already_started, pid}} -> GenServer.cast(pid, {:track, event})
          error -> error
        end
    end
  end

  @doc """
  Sends every buffered event to the Flagsmith events API, returning once done.
  """
  @spec flush(environment_key()) :: :ok | :noop | {:error, term()}
  def flush(environment_key) do
    case whereis(environment_key) do
      pid when is_pid(pid) -> GenServer.call(pid, :flush)
      :undefined -> :noop
    end
  end

  @doc false
  @spec processor_id(environment_key()) :: processor_identifier()
  def processor_id(environment_key), do: {__MODULE__, environment_key}

  @doc false
  @spec via_tuple(environment_key()) ::
          {:via, Registry, {Flagsmith.Registry, processor_identifier()}}
  def via_tuple(environment_key),
    do: {:via, Registry, {Flagsmith.Registry, processor_id(environment_key)}}

  @doc """
  Returns the pid of the Events.Processor process related to a given environment key,
  or :undefined if one can't be found.
  """
  @spec whereis(environment_key()) :: :undefined | pid
  def whereis(environment_key) do
    case Registry.lookup(Flagsmith.Registry, processor_id(environment_key)) do
      [] -> :undefined
      [{pid, _}] -> pid
    end
  end

  @doc """
  Starts and links a gen_server represented by this module, using a
  `t:Flagsmith.Configuration.t/0` as the basis to derive its registration name and
  inner details.
  """
  @spec start_link(Configuration.t()) :: GenServer.on_start()
  def start_link(%Configuration{environment_key: environment_key} = config),
    do: GenServer.start_link(__MODULE__, config, name: via_tuple(environment_key))

  #################################
  ########### GenServer Implementation / Internal
  #################################

  @impl GenServer
  def init(%Configuration{} = config) do
    Process.flag(:trap_exit, true)
    schedule_flush(config)
    {:ok, %__MODULE__{configuration: config}}
  end

  @impl GenServer
  def handle_cast({:track, event}, %__MODULE__{} = data) do
    case exposure_key(event) do
      nil ->
        {:noreply, buffer(data, event)}

      key ->
        case MapSet.member?(data.exposure_keys, key) do
          true ->
            Logger.debug(
              "Skipping duplicate #{@flag_exposure_event} event",
              feature_name: event.feature_name,
              identifier: event.identifier
            )

            {:noreply, data}

          false ->
            {:noreply,
             buffer(%{data | exposure_keys: MapSet.put(data.exposure_keys, key)}, event)}
        end
    end
  end

  @impl GenServer
  def handle_call(:flush, _from, %__MODULE__{} = data) do
    {result, data} = do_flush(data)
    {:reply, result, data}
  end

  @impl GenServer
  def handle_info(:flush, %__MODULE__{configuration: config} = data) do
    {_, data} = do_flush(data)
    schedule_flush(config)
    {:noreply, data}
  end

  def handle_info(_, data), do: {:noreply, data}

  @impl GenServer
  def terminate(_reason, %__MODULE__{} = data), do: do_flush(data)

  defp exposure_key(%{event: @flag_exposure_event} = event),
    do: {event.feature_name, event.identifier, event.value}

  defp exposure_key(_), do: nil

  defp buffer(%__MODULE__{buffer: buffer} = data, event) do
    data = %{data | buffer: [event | buffer]}

    case length(data.buffer) >= @max_buffered_events do
      true -> elem(do_flush(data), 1)
      false -> data
    end
  end

  defp do_flush(%__MODULE__{buffer: []} = data), do: {:noop, data}

  defp do_flush(%__MODULE__{configuration: config, buffer: buffer} = data) do
    events = Enum.reverse(buffer)

    case Flagsmith.Client.events_track(config, events) do
      {:ok, _} ->
        {:ok, %{data | buffer: [], exposure_keys: MapSet.new()}}

      {:error, reason} = error ->
        Logger.warning("Failed to send events to Flagsmith, keeping them to retry",
          reason: inspect(reason),
          events: length(events)
        )

        {error, %{data | buffer: Enum.take(buffer, @max_buffered_events)}}
    end
  end

  defp schedule_flush(%Configuration{events_flush_interval_milliseconds: interval}),
    do: Process.send_after(self(), :flush, interval)
end
