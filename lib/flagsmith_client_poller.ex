defmodule Flagsmith.Client.Poller do
  @moduledoc false
  require Logger

  alias Flagsmith.Configuration
  alias Flagsmith.Schemas

  @behaviour :gen_statem

  @type poller_identifier :: {__MODULE__, String.t()}
  @type environment_key :: String.t()
  @type identity_id :: String.t() | non_neg_integer()

  @default_refresh_in_milliseconds 60_000

  @enforce_keys [:configuration, :refresh]
  defstruct [
    :configuration,
    :environment,
    :refresh,
    :refresh_monitor
  ]

  #################################
  ########### API
  #################################

  @spec get_environment(Configuration.t()) :: {:ok, Schemas.Environment.t()} | {:error, term()}
  def get_environment(%Configuration{} = config),
    do: interact(config, :get_environment)

  @spec get_environment_flags(Configuration.t()) ::
          {:ok, map()} | {:error, term()}
  def get_environment_flags(%Configuration{} = config),
    do: interact(config, :get_flags)

  @spec get_identity_flags(Configuration.t(), identity_id(), list(map()) | map) ::
          {:ok, Schemas.Identity.t()} | {:error, term()}
  def get_identity_flags(%Configuration{} = config, identifier, traits),
    do: interact(config, {:get_identity_flags, identifier, traits})

  @spec statem_id(environment_key()) :: poller_identifier()
  def statem_id(environment_key), do: {__MODULE__, environment_key}

  @spec via_tuple(environment_key()) ::
          {:via, Registry, {Flagsmith.Registry, poller_identifier()}}
  def via_tuple(environment_key),
    do: {:via, Registry, {Flagsmith.Registry, statem_id(environment_key)}}

  @spec whereis(environment_key()) :: :undefined | pid
  def whereis(environment_key) do
    case Registry.lookup(Flagsmith.Registry, statem_id(environment_key)) do
      [] -> :undefined
      [{pid, _}] -> pid
    end
  end

  @spec interact(Configuration.t(), command :: term()) :: {:ok, term()} | {:error, term()}
  def interact(
        %Configuration{environment_key: environment_key} = config,
        command \\ :get_environment
      ) do
    case whereis(environment_key) do
      pid when is_pid(pid) ->
        :gen_statem.call(pid, command)

      :undefined ->
        case __MODULE__.Supervisor.start_child(config) do
          {:ok, pid} -> :gen_statem.call(pid, command)
          error -> error
        end
    end
  end

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

  @impl :gen_statem
  def callback_mode(), do: :handle_event_function

  @impl :gen_statem
  def init(%Configuration{} = config),
    do: {:ok, :loading, new_data(config), [{:next_event, :internal, :initial_load}]}

  @impl :gen_statem
  # the basic handles to reply with environment, flags data and identity
  def handle_event({:call, from}, :get_environment, _, %__MODULE__{environment: env}),
    do: {:keep_state_and_data, [{:reply, from, {:ok, env}}]}

  def handle_event({:call, from}, :get_flags, _, %__MODULE__{environment: env}) do
    {:keep_state_and_data, [{:reply, from, {:ok, Flagsmith.Client.extract_flags(env)}}]}
  end

  def handle_event({:call, from}, {:get_identity_flags, identifier, traits}, _, %__MODULE__{
        environment: env
      }) do
    identity = Schemas.Identity.from_id_traits(identifier, traits, env.api_key)

    flags =
      env
      |> Flagsmith.Engine.get_identity_feature_states(identity)
      |> Flagsmith.Client.extract_flags()

    {:keep_state_and_data, [{:reply, from, {:ok, flags}}]}
  end

  # handle to update the config. While this might be used in normal situations
  # it's here mostly so while on tests we can start the poller regularly
  # with a configuration and then from the mock resolution call update_refresh_rate
  # with a longer one
  # this way we are able to have the initial load & mock call, followed almost
  # immediately by a refresh call and from this second mock resolution we update it
  # back, to a longer one so when the mock resolves and the spawned process exits,
  # the new timeout will already be the longer one, allowing us to be sure it fires
  # only N times
  def handle_event({:call, from}, {:update_refresh_rate, timeout}, _, data),
    do: {:keep_state, %{data | refresh: timeout}, [{:reply, from, :ok}]}

  # on the initial load we do the request from the Poller itself as a blocking
  # non-async request. The reason for this is that we only want to answer client
  # requests once we have some data at all and if we fail to get the initial data
  # we don't have anything either to reply when requested
  # The reason we don't do this in the `init` call itself is because we want to be
  # able to mock and test this properly, so we need the statem to return from init
  # in order to provide a pid for the test processe to use
  def handle_event(:internal, :initial_load, :loading, %__MODULE__{configuration: config} = data) do
    case Flagsmith.Client.get_environment_request(config) do
      {:ok, environment} ->
        {:next_state, :on, %__MODULE__{data | environment: environment},
         [{:next_event, :internal, :set_refresh}]}

      error ->
        {:stop, error}
    end
  end

  # this just sets a timeout that fires an handle timeout event
  def handle_event(:internal, :set_refresh, :on, %__MODULE__{refresh: refresh}) do
    {:keep_state_and_data, [{{:timeout, :refresh}, refresh, nil}]}
  end

  # When the refresh timer fires we spawn a process for getting the environment,
  # with monitoring for this newly spawned process so that then our Poller
  # receives a message when the process runs through.
  #
  # The reason we spawn a process is so that these are completely asynchronous and
  # do not block the Poller from answering requests for data.
  # For instance, if the poller did itself the requests, like it does on initial load,
  # then if a client asked for the environment flags while it was refreshing, they
  # would be blocked until the request finished. This way they will not be, the caller
  # gets its request answered immediately with whatever is there  at that point.
  # Since we only let the Poller run when it is able to do the initial load we're
  # sure there's always going to be data available even if possibly "stale".
  #
  # We also set the `{pid, monitor}` tuple in our state data `:refresh_monitor` in
  # order to be able to match it down the line

  def handle_event({:timeout, :refresh}, _, _, %__MODULE__{configuration: config} = data) do
    pid_monitor_tuple =
      Process.spawn(Flagsmith.Client.Poller, :get_environment, [self(), config], [:monitor])

    {:keep_state, %{data | refresh_monitor: pid_monitor_tuple}, []}
  end

  # Here is the handle for the refresh messages. Once those spawned processes exit,
  # because they're being monitored here, this process will receive a msg with `:DOWN`
  # tuple from them, that contains the monitor reference, the pid of that process that
  # just exited and whatever is the exit value.
  #
  # if it's normal, then it means we will or have already received the message with
  # the result so we do nothing, if it's anything else the request might have thrown
  # an exception or something unexpected and we won't be receiving the result message
  # so we set a refresh timer again
  def handle_event(:info, {:DOWN, _, :process, _, :normal}, _, _),
    do: {:keep_state_and_data, []}

  def handle_event(
        :info,
        {:DOWN, ref, :process, pid, _},
        _,
        %__MODULE__{refresh_monitor: {pid, ref}} = data
      ),
      do: {:keep_state, %{data | refresh_monitor: nil}, [{:next_event, :internal, :set_refresh}]}

  # This is the message sent by the process spawned for doing the refresh request
  # Although there isn't any reason why we ought to receive a refresh message from
  # a process other than the one we have stored under the `:refresh_monitor` key
  # we still make sure it's matching.
  #
  # Then we just check if the response is an `:ok` tuple with an `Environment.t` 
  # we replace the `:environment` key on our statem data and following user queries
  # will receive the new env or flags. If not we let it stay as is.
  #
  # In both situations we set a new refresh timer to do it again.
  def handle_event(
        :info,
        {:refresh, pid, result},
        _,
        %__MODULE__{refresh_monitor: {pid, _ref}} = data
      ) do
    case result do
      {:ok, %Schemas.Environment{} = env} ->
        {:keep_state, %{data | refresh_monitor: nil, environment: env},
         [{:next_event, :internal, :set_refresh}]}

      error ->
        Logger.error(
          "#{inspect(__MODULE__)} failed to retrieve environment document: #{inspect(error)}"
        )

        {:keep_state, %{data | refresh_monitor: nil}, [{:next_event, :internal, :set_refresh}]}
    end
  end

  # We should never receive this message but I like having a catch all for info msgs
  # and just log.
  def handle_event(:info, unknown, _state, _data) do
    Logger.warn("#{inspect(__MODULE__)} received unexpected message: #{inspect(unknown)}")
    {:keep_state_and_data, []}
  end

  # Just a helper to return the initial data struct.
  defp new_data(%Configuration{environment_refresh_interval_milliseconds: refresh} = config) do
    refresh_milliseconds =
      case refresh do
        n when is_integer(n) and n > 0 -> n
        _ -> @default_refresh_in_milliseconds
      end

    %__MODULE__{configuration: config, refresh: refresh_milliseconds}
  end

  @doc false
  # this function is just so we can spawn a proper function with an MFA tuple
  def get_environment(pid, config) do
    resp = Flagsmith.Client.get_environment_request(config)

    send(pid, {:refresh, self(), resp})
  end
end
