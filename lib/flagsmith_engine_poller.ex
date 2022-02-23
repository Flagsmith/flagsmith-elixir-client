defmodule FlagsmithEngine.Poller do
  require Logger

  @moduledoc """
  The poller responsible for retrieving the environment from the Flagsmith API.
  """

  @behaviour :gen_statem

  # 60 seconds, times 1000 milliseconds, times 5 = 5 minutes
  @default_refresh_interval 60 * 1000 * 5

  @enforce_keys [:client]
  defstruct [
    :client,
    ets: __MODULE__,
    loaded: false,
    refresh_interval: @default_refresh_interval
  ]

  @default_api_url FlagsmithEngine.api_url()

  @doc """
  Returns the default child specification for the statem
  """
  def child_spec(args),
    do: %{
      id: Keyword.get(args, :name, __MODULE__),
      start: {__MODULE__, :start_link, [args]},
      type: :worker
    }

  #################################
  ########### API
  #################################

  @spec start_link() :: {:ok, pid()} | {:error, term()}
  @spec start_link(opts :: Keyword.t() | nil) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []),
    do:
      :gen_statem.start_link(
        {:local, Keyword.get(opts, :name, __MODULE__)},
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
    with {:ok, api_key} <- get_environment_api_key(options),
         {:ok, api_url} <- get_api_url(options),
         {:ok, client} <- Flagsmith.SDK.new(api_key, api_url),
         data <- %__MODULE__{client: client},
         data <- set_options(data, options) do
      {:ok, :starting, data, [{:next_event, :internal, :start}]}
    else
      {:error, error} ->
        {:stop, error}
    end
  end

  @impl :gen_statem
  def handle_event(:internal, :start, :starting, %__MODULE__{ets: ets_name}) do
    case :ets.new(ets_name, [:named_table]) do
      ^ets_name ->
        {:keep_state_and_data, [{:next_event, :internal, :load}]}

      error ->
        {:stop, {:error, {:creating_ets_table, error}}}
    end
  end

  def handle_event(:internal, :load, _, %__MODULE__{client: client} = _data) do
    case Flagsmith.SDK.API.flags_list(client) do
      {:ok, flags} ->
        {:keep_state_and_data, [{:next_event, :internal, {:cache, :flags, flags}}]}

      {:error, _error} = error ->
        Logger.error(IO.inspect(flagsmith_engine_poller: error))
        {:stop, error}
    end
  end

  def handle_event(:internal, {:cache, :flags, flags}, _, %__MODULE__{ets: ets} = data) do
    with remapped when is_list(remapped) <- prepare_flags_for_ets(flags),
         true <- :ets.insert(ets, remapped) do
      {:next_state, :loaded, %{data | loaded: true}, []}
    else
      _ ->
        :error
    end
  end

  # ETS stores elements as arbitrary length tuples, with the first element as the key
  # by default. It also has a specific query language that allows very fast retrieval
  # of elements by conditions, that's why we extract, ids and other details and place
  # them as elements in the final tuple, with the full feature as the last element.
  # the other elements allow querying on things like - is it enabled?, is it for this
  # identity?, environment?, etc.
  # The primary key is the feature id nonetheless, and not the full id.
  defp prepare_flags_for_ets(flags) do
    Enum.map(flags, fn %Flagsmith.Schemas.Features.FeatureState{
                         id: id,
                         enabled: enabled,
                         environment: environment,
                         identity: identity,
                         feature: %{id: f_id, name: name}
                       } = full_feature ->
      {f_id, enabled, id, environment, identity, name, full_feature}
    end)
  end

  defp get_environment_api_key(options) do
    case Keyword.get(options, :api_key, Application.get_env(FlagsmithEngine, :api_key)) do
      key when is_binary(key) -> {:ok, key}
      mismatched -> {:error, {:invalid_key, mismatched}}
    end
  end

  defp get_api_url(options) do
    case Keyword.get(options, :api_url, @default_api_url) do
      url when is_binary(url) -> {:ok, url}
      mismatched -> {:error, {:invalid_url, mismatched}}
    end
  end

  defp set_options(data, opts \\ []),
    do: Enum.reduce(opts, data, &set_option(&2, &1))

  defp set_option(data, {:interval, interval}) when is_integer(interval) and interval > 60000,
    do: %{data | refresh_interval: interval}

  defp set_option(data, _), do: data
end
