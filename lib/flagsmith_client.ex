defmodule Flagsmith.Client do
  require Logger

  alias Flagsmith.Schemas
  alias Flagsmith.Configuration
  alias Flagsmith.Client.Events

  @api_paths Flagsmith.Configuration.api_paths()
  @environment_header Flagsmith.Configuration.environment_header()
  @flag_exposure_event Events.Processor.flag_exposure_event()

  @type tesla_header_list :: [{String.t(), String.t()}]
  @type config_or_env :: Configuration.t() | Keyword.t() | Schemas.Environment.t()
  @type event_value :: String.t() | number() | boolean() | nil
  @type event_opts :: [
          identifier: String.t(),
          value: event_value(),
          traits: list(map() | Schemas.Traits.Trait.t()),
          metadata: map()
        ]

  @doc false
  @spec version() :: String.t()
  def version do
    # x-release-please-start-version
    "2.3.1"
    # x-release-please-end
  end

  @doc false
  @spec user_agent() :: String.t()
  def user_agent, do: "flagsmith-elixir-sdk/#{version()}"

  @doc """
  Create a `t:Flagsmith.Configuration.t/0` struct with the desired settings to use
  in requests.
  All settings are optional with exception of the `:environment_key` if not configured
  at the application level. 
  Non specified options will assume defaults, or if set at the application level use
  that.
  """
  @spec new(Keyword.t()) :: Configuration.t() | no_return()
  def new(opts \\ []),
    do: Configuration.build(opts)

  @spec http_client(Configuration.t()) :: Tesla.Client.t()
  defp http_client(%Configuration{
         environment_key: environment_key,
         api_url: api_url,
         request_timeout_milliseconds: timeout,
         custom_headers: custom_headers,
         retries: retries
       }) do
    Tesla.client([
      base_url_middleware(api_url),
      auth_middleware(environment_key),
      user_agent_middleware(),
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Retry, max_retries: retries},
      {Tesla.Middleware.Headers, custom_headers},
      {Tesla.Middleware.FollowRedirects, max_redirects: 5},
      {Tesla.Middleware.Timeout, timeout: timeout}
    ])
  end

  @doc """
  Returns an `:ok` tuple containing a `t:Flagsmith.Schemas.Environment.t/0` struct,
  either from the local evaluation or API depending on the configuration used, or an
  `:error` tuple if unable to. 

  Passing a `t:Flagsmith.Configuration.t/0` or options with `:enable_local_evaluation`
  as `true` will start a local process for the given api key used, if one is not 
  started yet, which requires you to be running the `Flagsmith.Supervisor`.
  """
  @spec get_environment(Configuration.t() | Keyword.t()) ::
          {:ok, Schemas.Environment.t()} | {:error, term()}
  def get_environment(configuration_or_opts \\ [])

  def get_environment(%Configuration{enable_local_evaluation: local?} = config) do
    case local? do
      true -> Flagsmith.Client.Poller.get_environment(config)
      false -> get_environment_request(config)
    end
  end

  def get_environment(opts) when is_list(opts),
    do: get_environment(new(opts))

  @doc false
  def get_environment_request(%Configuration{} = config) do
    case Tesla.get(http_client(config), @api_paths.environment) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok,
         body
         |> Schemas.Environment.from_response()
         |> Schemas.Environment.add_client_config(config)}

      error_resp ->
        return_error(error_resp)
    end
  end

  @doc """
  Returns an `:ok` tuple containing a list of `t:Flagsmith.Schemas.Flag.t/0` structs,
  either from the local evaluation or API depending on the configuration used, or an
  `:error` tuple if unable to. 

  Passing a `t:Flagsmith.Configuration.t/0` or options with `:enable_local_evaluation`
  as `true` will start a local process for the given api key used, if one is not 
  started yet, which requires you to be running the `Flagsmith.Supervisor`.
  """
  @spec get_environment_flags(config_or_env()) ::
          {:ok, Schemas.Flags.t()} | {:error, term()}
  def get_environment_flags(configuration_or_env_or_opts \\ [])

  def get_environment_flags(%Configuration{enable_local_evaluation: local?} = config) do
    case local? do
      true -> Flagsmith.Client.Poller.get_environment_flags(config)
      false -> get_environment_flags_request(config)
    end
  end

  def get_environment_flags(%Schemas.Environment{} = env),
    do: {:ok, build_flags(env)}

  def get_environment_flags(opts) when is_list(opts),
    do: get_environment_flags(new(opts))

  @doc false
  defp get_environment_flags_request(%Configuration{} = config) do
    case get_environment_request(config) do
      {:ok, %Schemas.Environment{} = env} ->
        {:ok, build_flags(env, config)}

      error ->
        error
    end
  end

  @doc false
  def build_flags(%Schemas.Environment{__configuration__: %Configuration{} = config} = env),
    do: build_flags(env, config)

  @doc false
  def build_flags(%Schemas.Environment{} = env, %Configuration{} = config) do
    env
    |> extract_flags()
    |> Schemas.Flags.new(config)
  end

  def build_flags(flags, %Configuration{} = config) when is_map(flags),
    do: Schemas.Flags.new(flags, config)

  def build_flags(flags, %Configuration{} = config) when is_list(flags) do
    flags
    |> extract_flags()
    |> Schemas.Flags.new(config)
  end

  @doc """
  Returns an `:ok` tuple containing a list of `t:Flagsmith.Schemas.Flag.t/0` structs,
  either from the local evaluation or API depending on the configuration used, or an
  `:error` tuple if unable to. The flags are retrieved based on a user identifier
  so take into account segments and traits. 

  Note: when using local evaluation there's no way to update the
  traits, the traits passed on to this function are used to check any segment rule
  specified on the `t:Flagsmith.Schemas.Environment.t/0` you're accessing. On the other
  hand, when using the live API evaluation the traits you pass will be used to update
  the traits associated with the identity you're specifying.

  Passing a `t:Flagsmith.Configuration.t/0` or options with `:enable_local_evaluation`
  as `true` will start a local process for the given api key used, if one is not 
  started yet, which requires you to be running the `Flagsmith.Supervisor`.
  """
  @spec get_identity_flags(
          Configuration.t() | Keyword.t(),
          String.t(),
          list(map() | Schemas.Traits.Trait.t()),
          boolean()
        ) ::
          {:ok, Schemas.Flags.t()} | {:error, term()}
  def get_identity_flags(configuration_or_opts \\ [], identifier, traits, transient \\ false)

  def get_identity_flags(
        %Configuration{enable_local_evaluation: local?} = config,
        identifier,
        traits,
        transient
      ) do
    case local? do
      true -> Flagsmith.Client.Poller.get_identity_flags(config, identifier, traits)
      false -> get_identity_flags_request(config, identifier, traits, transient)
    end
  end

  def get_identity_flags(opts, identifier, traits, transient) when is_list(opts),
    do: get_identity_flags(new(opts), identifier, traits, transient)

  @doc false
  def get_identity_flags_request(%Configuration{} = config, identifier, traits, transient) do
    query = build_identity_params(identifier, traits, transient)

    case Tesla.post(http_client(config), @api_paths.identities, query) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        with %Schemas.Identity{identity_features: identity_features} <-
               Schemas.Identity.from_response(body),
             flags <- build_flags(identity_features, config) do
          {:ok, flags}
        else
          error ->
            {:error, error}
        end

      error_resp ->
        return_error(error_resp)
    end
  end

  @doc """
  Returns a `t:Flagsmith.Schemas.Flag.t/0` by name, evaluated for an identity as
  `get_identity_flags/4` does, and records which variant of the feature the identity
  was exposed to.

  The exposure is sent as a `"$flag_exposure"` event, valued with the variant the
  identity was served, only when the flag is enabled and the identity is enrolled in a
  running experiment on the feature.

  Requires `:enable_events` to be `true` and the `Flagsmith.Supervisor` to be running.
  Returns what `get_flag/2` returns for the identity's flags, or an `:error` tuple if
  unable to get them.
  """
  @spec get_experiment_flag(
          Configuration.t() | Keyword.t(),
          feature_name :: String.t(),
          identifier :: String.t(),
          list(map() | Schemas.Traits.Trait.t())
        ) :: Schemas.Flag.t() | :not_found | term()
  def get_experiment_flag(configuration_or_opts, feature_name, identifier, traits \\ [])

  def get_experiment_flag(%Configuration{enable_events: false}, _, _, _),
    do: {:error, :events_disabled}

  def get_experiment_flag(%Configuration{} = config, feature_name, identifier, traits) do
    with {:ok, flags} <- get_identity_flags(config, identifier, traits) do
      flag = get_flag(flags, feature_name)

      case exposure_skip_reason(flag) do
        nil ->
          track_exposure_event(config, feature_name,
            identifier: identifier,
            value: flag.variant,
            traits: traits,
            metadata: %{experiment_id: flag.experiment.id}
          )

        reason ->
          Logger.debug("Not sending #{@flag_exposure_event}: #{reason}",
            feature_name: feature_name
          )
      end

      flag
    end
  end

  def get_experiment_flag(opts, feature_name, identifier, traits) when is_list(opts),
    do: get_experiment_flag(new(opts), feature_name, identifier, traits)

  @doc """
  Sends an event to Flagsmith, e.g. a conversion for experiments to measure.

  Options:
  - `:identifier` -> the identity the event happened to
  - `:value` -> a string, number or boolean, sent as a string
  - `:traits` -> the identity's traits, in the format `get_identity_flags/4` takes
  - `:metadata` -> a map of additional data

  Events are buffered and sent in batches, so this returns `:ok` without waiting for
  the event to be sent. Requires `:enable_events` to be `true` and the
  `Flagsmith.Supervisor` to be running. Event names starting with `$` are reserved
  for Flagsmith's own events.
  """
  @spec track_event(Configuration.t() | Keyword.t(), event :: String.t(), event_opts()) ::
          :ok | {:error, term()}
  def track_event(configuration_or_opts, event, opts \\ [])

  def track_event(%Configuration{enable_events: false}, _, _),
    do: {:error, :events_disabled}

  def track_event(%Configuration{}, "$" <> _ = event, _) when event != @flag_exposure_event,
    do: {:error, {:reserved_event_name, event}}

  def track_event(%Configuration{} = config, event, opts) when is_binary(event),
    do: buffer_event(config, event, nil, opts)

  def track_event(opts, event, event_opts) when is_list(opts),
    do: track_event(new(opts), event, event_opts)

  @doc """
  Sends a `"$flag_exposure"` event to Flagsmith, recording that an identity was shown
  a variant of a feature. `get_experiment_flag/4` sends these by itself.

  Takes the same options as `track_event/3`, with `:value` being the variant, and
  `:identifier` being required to reconcile the exposure with the identity's events.
  Exposures equal in feature, identifier and value are sent once per flush interval.
  """
  @spec track_exposure_event(
          Configuration.t() | Keyword.t(),
          feature_name :: String.t(),
          event_opts()
        ) :: :ok | {:error, term()}
  def track_exposure_event(configuration_or_opts, feature_name, opts \\ [])

  def track_exposure_event(%Configuration{enable_events: false}, _, _),
    do: {:error, :events_disabled}

  def track_exposure_event(%Configuration{} = config, feature_name, opts) do
    case Keyword.get(opts, :identifier) do
      identifier when is_binary(identifier) and identifier != "" ->
        buffer_event(config, @flag_exposure_event, feature_name, opts)

      _ ->
        {:error, :identifier_required}
    end
  end

  def track_exposure_event(opts, feature_name, event_opts) when is_list(opts),
    do: track_exposure_event(new(opts), feature_name, event_opts)

  @doc """
  Return all flags from an environment as a list.
  If a `t:Flagsmith.Schemas.Environment.t/0` is passed instead of a 
  `t:Flagsmith.Configuration.t/0` or list of options, then the flags are extracted
  from it.
  """
  @spec all_flags(config_or_env()) :: list(Schemas.Flag.t())
  def all_flags(config_or_opts_or_env_or_flags \\ [])

  def all_flags(%Schemas.Environment{} = env) do
    env
    |> Flagsmith.Engine.get_environment_feature_states()
    |> Enum.map(&Schemas.Flag.from(&1))
  end

  def all_flags(%Schemas.Flags{flags: flags}),
    do: Enum.map(flags, fn {_, flag} -> flag end)

  def all_flags(%Configuration{} = config) do
    case get_environment(config) do
      {:ok, %Schemas.Environment{} = env} -> all_flags(env)
      error -> error
    end
  end

  def all_flags(opts) when is_list(opts),
    do: all_flags(new(opts))

  @doc """
  Returns the `:enabled` status of a feature by name, or `:not_found` if the feature
  doesn't exist.

  If a `t:Flagsmith.Schemas.Environment.t/0` is passed instead of a 
  `t:Flagsmith.Configuration.t/0` or list of options, then the feature is evaluated
  from that environment, otherwise a local evaluation or api call is executed
  according to the configuration or passed options.
  """
  @spec is_feature_enabled(config_or_env(), feature_name :: String.t()) ::
          boolean() | :not_found | term()
  def is_feature_enabled(configuration_or_env_or_opts \\ [], feature_name) do
    case get_flag(configuration_or_env_or_opts, feature_name) do
      %Schemas.Flag{enabled: enabled?} ->
        enabled?

      error ->
        error
    end
  end

  @doc """
  Returns a `t:Flagsmith.Schemas.Flag.t/0` by name, or `:not_found` if the feature
  doesn't exist.

  If a `t:Flagsmith.Schemas.Environment.t/0` is passed instead of a 
  `t:Flagsmith.Configuration.t/0` or list of options, then the feature is looked up
  in that environment, otherwise a local evaluation or api call is executed
  according to the configuration or passed options.
  """
  @spec get_feature_value(config_or_env(), feature_name :: String.t()) ::
          :not_found | term()
  def get_feature_value(configuration_or_env_or_opts \\ [], feature_name) do
    case get_flag(configuration_or_env_or_opts, feature_name) do
      %Schemas.Flag{value: value} ->
        value

      error ->
        error
    end
  end

  @doc """
  Returns a `t:Flagsmith.Schemas.Flag.t/0` by name. If the feature doesn't exist, 
  it returns `:not_found` by default or in case `default_flag_handler` has been set
  returns what the call to that function with the feature name returns.

  If a `t:Flagsmith.Schemas.Environment.t/0` is passed instead of a 
  `t:Flagsmith.Configuration.t/0` or list of options, then the feature is looked up
  in that environment, otherwise a local evaluation or api call is executed
  according to the configuration or passed options.
  """
  @spec get_flag(config_or_env() | Schemas.Flags.t(), feature_name :: String.t()) ::
          Schemas.Flag.t() | :not_found | term()
  def get_flag(configuration_or_env_or_opts \\ [], feature_name)

  def get_flag(
        %Schemas.Environment{__configuration__: %{default_flag_handler: handler}} = env,
        feature_name
      ) do
    env
    |> extract_flags()
    |> Map.get(feature_name)
    |> case do
      %Schemas.Flag{} = flag ->
        maybe_track(flag, env)

      _ when is_function(handler, 1) ->
        handler.(feature_name)

      _ ->
        :not_found
    end
  end

  def get_flag(
        %Schemas.Flags{
          __configuration__: %{default_flag_handler: handler} = config,
          flags: flags
        },
        feature_name
      ) do
    case Map.get(flags, feature_name) do
      %Schemas.Flag{} = flag ->
        maybe_track(flag, config)

      _ when is_function(handler, 1) ->
        handler.(feature_name)

      _ ->
        :not_found
    end
  end

  def get_flag(%Configuration{default_flag_handler: handler} = config, feature_name) do
    case get_environment(config) do
      {:ok, %Schemas.Environment{} = env} -> get_flag(env, feature_name)
      _error when is_function(handler, 1) -> handler.(feature_name)
      error -> error
    end
  end

  def get_flag(opts, feature_name) when is_list(opts),
    do: get_flag(new(opts), feature_name)

  @doc false
  # Submits a map of `feature_id => number_of_accesses` to the Flagsmith analytics
  # endpoint for usage tracking.
  @spec analytics_track(Configuration.t() | Keyword.t(), map()) :: {:ok, map()} | {:error, term}
  def analytics_track(configuration_or_env_or_opts \\ [], tracking)

  def analytics_track(%Configuration{} = config, tracking) do
    case Tesla.post(http_client(config), @api_paths.analytics, tracking) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok, body}

      error_resp ->
        return_error(error_resp)
    end
  end

  def analytics_track(opts, tracking)
      when is_list(opts) and is_map(tracking) and not is_struct(tracking),
      do: analytics_track(new(opts), tracking)

  @doc false
  # Submits a batch of events to the Flagsmith events API.
  @spec events_track(Configuration.t(), list(Events.Processor.event())) ::
          {:ok, term()} | {:error, term()}
  def events_track(%Configuration{events_api_url: events_api_url} = config, events) do
    case Tesla.post(
           http_client(%{config | api_url: events_api_url}),
           @api_paths.events,
           %{events: events}
         ) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok, body}

      error_resp ->
        return_error(error_resp)
    end
  end

  @doc false
  # Given an `t:Flagsmith.Schemas.Environment.t/0` or a list composed of
  # `t:Flagsmith.Schemas.Environment.FeatureState.t/0` or
  # `t:Flagsmith.Schemas.Features.FeatureState.t/0` return a map composed of the
  # features names as keys and the features as `t:Flagsmith.Schemas.Flag.t/0`.
  @spec extract_flags(
          Schemas.Environment.t()
          | list(Schemas.Features.FeatureState.t() | Schemas.Environment.FeatureState.t())
        ) :: %{String.t() => Schemas.Flag.t()}
  defp extract_flags(%Schemas.Environment{} = env) do
    env
    |> Flagsmith.Engine.get_environment_feature_states()
    |> Enum.reduce(%{}, fn feature_state, acc ->
      %Schemas.Flag{feature_name: name} = flag = Schemas.Flag.from(feature_state)
      Map.put(acc, name, flag)
    end)
  end

  defp extract_flags(feature_states) when is_list(feature_states) do
    Enum.reduce(feature_states, %{}, fn feature_state, acc ->
      %Schemas.Flag{feature_name: name} = flag = Schemas.Flag.from(feature_state)
      Map.put(acc, name, flag)
    end)
  end

  defp maybe_track(feature_flag, environment) do
    Flagsmith.Client.Analytics.Processor.track(feature_flag, environment)

    feature_flag
  end

  defp exposure_skip_reason(%Schemas.Flag{enabled: false}), do: "feature is disabled"

  defp exposure_skip_reason(%Schemas.Flag{experiment: %{in_experiment: true}, variant: nil}),
    do: "flag has no variant"

  defp exposure_skip_reason(%Schemas.Flag{experiment: %{in_experiment: true}}), do: nil

  defp exposure_skip_reason(%Schemas.Flag{}), do: "identity is not in a running experiment"
  defp exposure_skip_reason(_), do: "feature not found"

  defp buffer_event(%Configuration{} = config, event, feature_name, opts) do
    with {:ok, value} <- event_value(Keyword.get(opts, :value)) do
      Events.Processor.track(
        %{
          event: event,
          feature_name: feature_name,
          identifier: Keyword.get(opts, :identifier),
          value: value,
          traits: event_traits(Keyword.get(opts, :traits)),
          metadata: Map.put(Keyword.get(opts, :metadata) || %{}, :sdk_version, version()),
          timestamp: System.os_time(:millisecond)
        },
        config
      )
    end
  end

  defp event_value(value) when is_nil(value) or is_binary(value), do: {:ok, value}
  defp event_value(value) when is_number(value) or is_boolean(value), do: {:ok, to_string(value)}
  defp event_value(value), do: {:error, {:invalid_value, value}}

  defp event_traits([_ | _] = traits) do
    traits
    |> Schemas.Traits.Trait.from()
    |> Map.new(fn %{trait_key: key, trait_value: value} -> {key, value} end)
  end

  defp event_traits(_), do: nil

  defp build_identity_params(identifier, [_ | _] = traits, transient) do
    %{
      identifier: identifier,
      traits: Schemas.Traits.Trait.from(traits),
      transient: transient
    }
  end

  defp build_identity_params(identifier, _, transient),
    do: %{identifier: identifier, transient: transient}

  @doc false
  @spec auth_middleware(environment_key :: String.t()) ::
          {Tesla.Middleware.Headers, tesla_header_list()}
  def auth_middleware(environment_key),
    do: {Tesla.Middleware.Headers, auth_header(environment_key)}

  @doc false
  @spec user_agent_middleware() ::
          {Tesla.Middleware.Headers, tesla_header_list()}
  def user_agent_middleware(),
    do: {Tesla.Middleware.Headers, [{"user-agent", user_agent()}]}

  @doc false
  @spec base_url_middleware(base_url :: String.t()) ::
          {Tesla.Middleware.BaseUrl, String.t()}
  def base_url_middleware(base_url),
    do: {Tesla.Middleware.BaseUrl, base_url}

  @spec auth_header(environment_key :: String.t()) :: tesla_header_list()
  defp auth_header(environment_key), do: [{@environment_header, environment_key}]

  defp return_error({:ok, %{body: body}}), do: {:error, body}
  defp return_error({:error, _} = error), do: error
end
