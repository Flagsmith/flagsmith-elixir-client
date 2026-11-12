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
  @max_attempts 3
  @request_timeout_milliseconds 3000
  @retry_base_milliseconds if(Mix.env() == :test, do: 20, else: 1000)
  @default_close_timeout_milliseconds 5000
  # Statuses that a later attempt may not get, besides server errors.
  @retried_statuses [408, 429]
  # Statuses meaning the events API refuses the environment key.
  @refused_statuses [401, 403]

  @enforce_keys [:configuration]
  defstruct [
    :configuration,
    buffer: :queue.new(),
    buffered: 0,
    # Whether events were tracked since the last attempt to send the buffer.
    unsent: false,
    refused: false,
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
  Sends the events tracked so far to the Flagsmith events API, retries included, and
  returns once each of them has been delivered, dropped, or kept for the next flush.
  Returns `:noop` when there is nothing to send, including when the buffer only holds
  events already kept from a failed flush, which the next timed flush sends.
  """
  @spec flush(environment_key()) :: :ok | :noop | {:error, term()}
  def flush(environment_key) do
    case whereis(environment_key) do
      pid when is_pid(pid) -> GenServer.call(pid, :flush, :infinity)
      :undefined -> :noop
    end
  end

  @doc """
  Sends the buffered events, and stops the processor, waiting for at most `timeout`
  milliseconds. Events not sent by then are dropped: a processor still sending when
  the timeout expires, e.g. retrying a flush already running, is killed.
  """
  @spec close(environment_key(), non_neg_integer()) :: :ok | :noop | {:error, term()}
  def close(environment_key, timeout \\ @default_close_timeout_milliseconds) do
    case whereis(environment_key) do
      pid when is_pid(pid) ->
        deadline = System.monotonic_time(:millisecond) + timeout

        try do
          GenServer.call(pid, {:close, deadline}, timeout)
        catch
          # The processor is still sending a batch, which may take several more attempts.
          :exit, {:timeout, _} ->
            Logger.warning("Gave up sending events after #{timeout} milliseconds while closing")
            kill(pid)
            {:error, :timeout}

          :exit, {reason, _} when reason in [:noproc, :normal, :shutdown] ->
            :noop
        end

      :undefined ->
        :noop
    end
  end

  # Kills the processor, returning once it's gone. It traps exits, so only :kill stops
  # it while it's busy sending; its supervisor doesn't restart it, being :temporary.
  defp kill(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
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
  def handle_cast({:track, event}, %__MODULE__{refused: true} = data) do
    Logger.debug("Not tracking #{event.event} event: the events API refused the environment key")
    {:noreply, data}
  end

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
  def handle_call(:flush, _from, %__MODULE__{unsent: false} = data),
    do: {:reply, :noop, data}

  def handle_call(:flush, _from, %__MODULE__{} = data) do
    {result, data} = do_flush(data, :infinity)
    {:reply, result, data}
  end

  def handle_call({:close, deadline}, _from, %__MODULE__{} = data) do
    {result, _data} = do_flush(data, deadline)
    {:stop, :normal, result, %{data | buffer: :queue.new(), buffered: 0}}
  end

  @impl GenServer
  def handle_info(:flush, %__MODULE__{configuration: config} = data) do
    {_, data} = do_flush(data, :infinity)
    schedule_flush(config)
    {:noreply, data}
  end

  def handle_info(_, data), do: {:noreply, data}

  @impl GenServer
  def terminate(_reason, %__MODULE__{} = data) do
    do_flush(data, System.monotonic_time(:millisecond) + @default_close_timeout_milliseconds)
  end

  defp exposure_key(%{event: @flag_exposure_event} = event),
    do: {event.feature_name, event.identifier, event.value}

  defp exposure_key(_), do: nil

  # A full buffer drops its oldest event for the new one. Filling it up sends it
  # without waiting for the flush interval.
  defp buffer(%__MODULE__{buffered: @max_buffered_events} = data, event) do
    {{:value, dropped}, buffer} = :queue.out(data.buffer)
    Logger.warning("Event buffer is full, dropping the oldest #{dropped.event} event")
    %{data | buffer: :queue.in(event, buffer), unsent: true}
  end

  defp buffer(%__MODULE__{} = data, event) do
    data = %{
      data
      | buffer: :queue.in(event, data.buffer),
        buffered: data.buffered + 1,
        unsent: true
    }

    case data.buffered do
      @max_buffered_events -> elem(do_flush(data, :infinity), 1)
      _ -> data
    end
  end

  defp do_flush(%__MODULE__{buffered: 0} = data, _deadline), do: {:noop, data}

  defp do_flush(%__MODULE__{configuration: config} = data, deadline) do
    events = :queue.to_list(data.buffer)
    sent = %{data | buffer: :queue.new(), buffered: 0, unsent: false, exposure_keys: MapSet.new()}

    case deliver(config, events, deadline, 1) do
      :delivered ->
        {:ok, sent}

      {:dropped, reason} ->
        {{:error, reason}, sent}

      {:refused, reason} ->
        Logger.error("The events API refused the environment key, stopping event tracking")
        {{:error, reason}, %{sent | refused: true}}

      {:kept, reason} ->
        Logger.warning("Failed to send events to Flagsmith, keeping them for the next flush",
          reason: inspect(reason),
          events: length(events)
        )

        {{:error, reason}, %{data | unsent: false}}
    end
  end

  # Sends a batch up to @max_attempts times, backing off with full jitter between
  # attempts, until `deadline`. Returns what became of the batch: delivered, dropped
  # (rejected by the events API, or failed with a 500 on its last attempt), refused
  # (the events API refuses the environment key), or kept for the next flush.
  defp deliver(config, events, deadline, attempt) do
    case remaining(deadline) do
      0 ->
        {:kept, :timeout}

      remaining ->
        config
        |> Flagsmith.Client.events_track(events, min(remaining, @request_timeout_milliseconds))
        |> handle_attempt(config, events, deadline, attempt)
    end
  end

  defp handle_attempt({:ok, status}, _, _, _, _) when status in 200..299, do: :delivered

  defp handle_attempt({:ok, status}, _, _, _, _) when status in @refused_statuses,
    do: {:refused, {:status, status}}

  defp handle_attempt({:ok, status}, _, events, _, _)
       when status < 500 and status not in @retried_statuses do
    Logger.warning(
      "The events API rejected #{length(events)} events with #{status}, dropping them"
    )

    {:dropped, {:status, status}}
  end

  defp handle_attempt({:ok, 500}, _, events, _, @max_attempts) do
    Logger.warning("The events API failed #{length(events)} events with 500, dropping them")
    {:dropped, {:status, 500}}
  end

  defp handle_attempt(result, _, _, _, @max_attempts), do: {:kept, failure(result)}

  defp handle_attempt(result, config, events, deadline, attempt) do
    Logger.warning(
      "Failed to send #{length(events)} events, attempt #{attempt} of #{@max_attempts}",
      reason: inspect(failure(result))
    )

    backoff = :rand.uniform(@retry_base_milliseconds * 2 ** (attempt - 1) + 1) - 1

    case remaining(deadline) do
      remaining when remaining <= backoff ->
        {:kept, failure(result)}

      _ ->
        Process.sleep(backoff)
        deliver(config, events, deadline, attempt + 1)
    end
  end

  defp failure({:ok, status}), do: {:status, status}
  defp failure({:error, reason}), do: reason

  # As an atom, :infinity compares greater than any number, e.g. in min/2.
  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp schedule_flush(%Configuration{events_flush_interval_milliseconds: interval}),
    do: Process.send_after(self(), :flush, interval)
end
