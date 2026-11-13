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
  @close_margin_milliseconds 500
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
    exposure_keys: MapSet.new(),
    # The batch being sent, by a task, so that the processor keeps buffering events
    # (and applying the buffer's limit) while it waits on the events API.
    sending: nil,
    # Callers of flush/1 waiting for the batch being sent.
    flush_waiters: [],
    # Callers of flush/1 who arrived while a batch was being sent, with events tracked
    # since: they wait for one more batch, then get a reply whatever is tracked meanwhile.
    next_flush_waiters: [],
    # The caller of close/2, once closing.
    closing: nil
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
  Never exits: returns `{:error, :closed}` if the processor is closed meanwhile.
  """
  @spec flush(environment_key()) :: :ok | :noop | {:error, term()}
  def flush(environment_key) do
    case whereis(environment_key) do
      pid when is_pid(pid) ->
        try do
          GenServer.call(pid, :flush, :infinity)
        catch
          # The processor stopped between being looked up and called.
          :exit, {reason, _} when reason in [:noproc, :normal, :shutdown] -> :noop
          :exit, {reason, _} -> {:error, reason}
        end

      :undefined ->
        :noop
    end
  end

  @doc """
  Sends the buffered events, and stops the processor, returning after at most
  `timeout` milliseconds. Events not sent by then are dropped, and a batch still being
  sent, e.g. retried by a flush already running, is abandoned: no attempt to send it
  is made after this returns.
  """
  @spec close(environment_key(), non_neg_integer()) :: :ok | :noop | {:error, term()}
  def close(environment_key, timeout \\ @default_close_timeout_milliseconds) do
    case whereis(environment_key) do
      pid when is_pid(pid) ->
        try do
          # The processor replies by the deadline itself; the margin only covers one
          # that can't, for which it's killed.
          GenServer.call(pid, {:close, timeout}, timeout + @close_margin_milliseconds)
        catch
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
  # it; its supervisor doesn't restart it, being :temporary.
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
  def handle_call(:flush, from, %__MODULE__{sending: %{}, unsent: true} = data),
    do: {:noreply, %{data | next_flush_waiters: [from | data.next_flush_waiters]}}

  def handle_call(:flush, from, %__MODULE__{sending: %{}} = data),
    do: {:noreply, add_flush_waiter(data, from)}

  def handle_call(:flush, _from, %__MODULE__{unsent: false} = data),
    do: {:reply, :noop, data}

  def handle_call(:flush, from, %__MODULE__{} = data),
    do: {:noreply, data |> send_batch(:infinity) |> add_flush_waiter(from)}

  # Already closing: the first caller is the one waiting for the buffered events.
  def handle_call({:close, _timeout}, _from, %__MODULE__{closing: %{}} = data),
    do: {:reply, :noop, data}

  def handle_call({:close, timeout}, from, %__MODULE__{} = data) do
    Process.send_after(self(), :close_timeout, timeout)
    deadline = System.monotonic_time(:millisecond) + timeout
    closing = %{from: from, timeout: timeout, deadline: deadline, final_batch: false}

    case data.sending do
      # Waits for the batch being sent, until the deadline, then sends what's left.
      %{} -> {:noreply, %{data | closing: closing}}
      nil -> close_next(%{data | closing: closing}, :noop)
    end
  end

  @impl GenServer
  def handle_info(:flush, %__MODULE__{configuration: config} = data) do
    schedule_flush(config)

    case data do
      %{sending: nil, closing: nil} -> {:noreply, send_batch(data, :infinity)}
      _ -> {:noreply, data}
    end
  end

  def handle_info({ref, outcome}, %__MODULE__{sending: %{task: %Task{ref: ref}}} = data) do
    Process.demonitor(ref, [:flush])
    sent(data, outcome)
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %__MODULE__{sending: %{task: %Task{ref: ref}}} = data
      ),
      do: sent(data, {:kept, reason})

  def handle_info(:close_timeout, %__MODULE__{closing: %{timeout: timeout}} = data) do
    Logger.warning("Gave up sending events after #{timeout} milliseconds while closing")
    stop_closing(abandon_batch(data), {:error, :timeout})
  end

  def handle_info(_, data), do: {:noreply, data}

  @impl GenServer
  def terminate(_reason, %__MODULE__{} = data) do
    data = abandon_batch(data)

    case take_batch(data) do
      nil ->
        :noop

      {events, data} ->
        deadline = System.monotonic_time(:millisecond) + @default_close_timeout_milliseconds
        apply_outcome(data, events, deliver(data.configuration, events, deadline, 1))
    end
  end

  defp exposure_key(%{event: @flag_exposure_event} = event),
    do: {event.feature_name, event.identifier, event.value}

  defp exposure_key(_), do: nil

  # A full buffer drops its oldest event for the new one. Filling it up sends it
  # without waiting for the flush interval, or as soon as the batch being sent is done.
  defp buffer(%__MODULE__{buffered: @max_buffered_events} = data, event) do
    {{:value, dropped}, buffer} = :queue.out(data.buffer)
    Logger.warning("Event buffer is full, dropping the oldest #{dropped.event} event")
    forget_exposures(%{data | buffer: :queue.in(event, buffer), unsent: true}, [dropped])
  end

  defp buffer(%__MODULE__{} = data, event) do
    data = %{
      data
      | buffer: :queue.in(event, data.buffer),
        buffered: data.buffered + 1,
        unsent: true
    }

    case {data.buffered, data.sending, data.closing} do
      {@max_buffered_events, nil, nil} -> send_batch(data, :infinity)
      _ -> data
    end
  end

  defp add_flush_waiter(data, from), do: %{data | flush_waiters: [from | data.flush_waiters]}

  # Starts sending the buffered events, in a task, unless there are none.
  defp send_batch(%__MODULE__{configuration: config} = data, deadline) do
    case take_batch(data) do
      nil ->
        data

      {events, data} ->
        task = Task.async(fn -> deliver(config, events, deadline, 1) end)
        %{data | sending: %{task: task, events: events}}
    end
  end

  defp take_batch(%__MODULE__{buffered: 0}), do: nil

  defp take_batch(%__MODULE__{} = data),
    do: {:queue.to_list(data.buffer), %{data | buffer: :queue.new(), buffered: 0, unsent: false}}

  # Kills the task sending a batch, if any, putting the batch back in the buffer.
  defp abandon_batch(%__MODULE__{sending: nil} = data), do: data

  defp abandon_batch(%__MODULE__{sending: %{task: task, events: events}} = data) do
    Task.shutdown(task, :brutal_kill)
    keep(%{data | sending: nil}, events)
  end

  # The batch being sent is done with: replies to the callers of flush/1 waiting for it,
  # and sends one more batch for those who arrived meanwhile, with events tracked since.
  defp sent(%__MODULE__{sending: %{events: events}} = data, outcome) do
    {result, data} = apply_outcome(%{data | sending: nil}, events, outcome)
    reply_all(data.flush_waiters, result)
    data = %{data | flush_waiters: []}

    cond do
      data.closing != nil ->
        close_next(data, result)

      data.next_flush_waiters != [] and data.unsent ->
        data = send_batch(data, :infinity)
        {:noreply, %{data | flush_waiters: data.next_flush_waiters, next_flush_waiters: []}}

      true ->
        reply_all(data.next_flush_waiters, result)
        data = %{data | next_flush_waiters: []}

        # Events tracked meanwhile filled the buffer up; a kept batch alone doesn't.
        case {data.buffered, data.unsent} do
          {@max_buffered_events, true} -> {:noreply, send_batch(data, :infinity)}
          _ -> {:noreply, data}
        end
    end
  end

  defp reply_all(callers, reply), do: Enum.each(callers, &GenServer.reply(&1, reply))

  # Sends the buffer once while closing, by the deadline, then stops.
  defp close_next(%__MODULE__{closing: %{final_batch: false} = closing} = data, result) do
    case send_batch(data, closing.deadline) do
      %{sending: nil} = data -> stop_closing(data, result)
      data -> {:noreply, %{data | closing: %{closing | final_batch: true}}}
    end
  end

  defp close_next(%__MODULE__{} = data, result), do: stop_closing(data, result)

  defp stop_closing(%__MODULE__{closing: closing} = data, result) do
    GenServer.reply(closing.from, result)
    reply_all(data.flush_waiters ++ data.next_flush_waiters, {:error, :closed})

    {:stop, :normal,
     %{
       data
       | buffer: :queue.new(),
         buffered: 0,
         flush_waiters: [],
         next_flush_waiters: [],
         closing: nil
     }}
  end

  # What became of a batch: forgets it once delivered or dropped, and puts it back in
  # the buffer, ahead of the events tracked since, when kept for the next flush.
  defp apply_outcome(data, events, outcome) do
    case outcome do
      :delivered ->
        {:ok, forget_exposures(data, events)}

      {:dropped, reason} ->
        {{:error, reason}, forget_exposures(data, events)}

      {:refused, reason} ->
        Logger.error("The events API refused the environment key, stopping event tracking")

        {{:error, reason},
         %{
           data
           | buffer: :queue.new(),
             buffered: 0,
             unsent: false,
             refused: true,
             exposure_keys: MapSet.new()
         }}

      {:kept, reason} ->
        Logger.warning("Failed to send events to Flagsmith, keeping them for the next flush",
          reason: inspect(reason),
          events: length(events)
        )

        {{:error, reason}, keep(data, events)}
    end
  end

  defp keep(data, events) do
    {dropped, kept} =
      Enum.split(events ++ :queue.to_list(data.buffer), -@max_buffered_events)

    if dropped != [],
      do: Logger.warning("Event buffer is full, dropping the oldest #{length(dropped)} events")

    forget_exposures(%{data | buffer: :queue.from_list(kept), buffered: length(kept)}, dropped)
  end

  # Forgets the exposures among events no longer buffered, so that they're tracked again.
  defp forget_exposures(data, events) do
    keys = events |> Enum.map(&exposure_key/1) |> Enum.reject(&is_nil/1) |> MapSet.new()
    %{data | exposure_keys: MapSet.difference(data.exposure_keys, keys)}
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
