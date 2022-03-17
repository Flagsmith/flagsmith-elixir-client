defmodule Flagsmith.Client do
  alias Flagsmith.Schemas
  alias Flagsmith.Configuration

  @api_paths Flagsmith.Configuration.api_paths()
  @environment_header Flagsmith.Configuration.environment_header()

  @type tesla_header_list :: [{String.t(), String.t()}]
  @type config_or_env :: Configuration.t() | Keyword.t() | Schemas.Environment.t()

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
          list(map() | Schemas.Traits.Trait.t())
        ) ::
          {:ok, Schemas.Flags.t()} | {:error, term()}
  def get_identity_flags(configuration_or_opts \\ [], identifier, traits)

  def get_identity_flags(
        %Configuration{enable_local_evaluation: local?} = config,
        identifier,
        traits
      ) do
    case local? do
      true -> Flagsmith.Client.Poller.get_identity_flags(config, identifier, traits)
      false -> get_identity_flags_request(config, identifier, traits)
    end
  end

  def get_identity_flags(opts, identifier, traits) when is_list(opts),
    do: get_identity_flags(new(opts), identifier, traits)

  @doc false
  def get_identity_flags_request(%Configuration{} = config, identifier, traits) do
    query = build_identity_params(identifier, traits)

    case Tesla.post(http_client(config), @api_paths.identities, query) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        with %Schemas.Identity{flags: flags} <- Schemas.Identity.from_response(body),
             flags <- build_flags(flags, config) do
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

  defp build_identity_params(identifier, [_ | _] = traits) do
    %{
      identifier: identifier,
      traits: Schemas.Traits.Trait.from(traits)
    }
  end

  defp build_identity_params(identifier, _),
    do: %{identifier: identifier}

  @doc false
  @spec auth_middleware(environment_key :: String.t()) ::
          {Tesla.Middleware.Headers, tesla_header_list()}
  def auth_middleware(environment_key),
    do: {Tesla.Middleware.Headers, auth_header(environment_key)}

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
