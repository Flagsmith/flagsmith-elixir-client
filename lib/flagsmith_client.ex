defmodule Flagsmith.Client do
  alias Flagsmith.Schemas
  alias Flagsmith.Configuration

  @api_paths Flagsmith.Configuration.api_paths()
  @environment_header Flagsmith.Configuration.environment_header()

  @type tesla_header_list :: [{String.t(), String.t()}]

  @doc """
  Create a `t:Flagsmith.Configuration.t` struct with the desired settings to use
  in requests.
  All settings are optional with exception of the `:environment_key` if not configured
  at the application level. 
  Non specified options will assume defaults, or if set at the application level use
  that.
  """
  @spec new(Keyword.t()) :: {:ok, Configuration.t()} | no_return()
  def new(opts \\ []),
    do: Configuration.build(opts)

  @doc false
  @spec http_client(Configuration.t()) :: Tesla.Client.t()
  def http_client(%Configuration{
        environment_key: environment_key,
        api_url: api_url,
        request_timeout_milliseconds: timeout
      }) do
    Tesla.client([
      base_url_middleware(api_url),
      auth_middleware(environment_key),
      Tesla.Middleware.JSON,
      {Tesla.Middleware.FollowRedirects, max_redirects: 5},
      {Tesla.Middleware.Timeout, timeout: timeout}
    ])
  end

  @doc """
  Returns an `:ok` tuple containing a `t:Flagsmith.Schemas.Environment.t` struct,
  either from the local evaluation or API depending on the configuration used, or an
  `:error` tuple if unable to. 

  Passing a `t:Flagsmith.Configuration.t` or options with `:enable_local_evaluation`
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
        {:ok, Schemas.Environment.from_response(body)}

      error_resp ->
        return_error(error_resp)
    end
  end

  @doc """
  Returns an `:ok` tuple containing a list of `t:Flagsmith.Schemas.Flag.t` structs,
  either from the local evaluation or API depending on the configuration used, or an
  `:error` tuple if unable to. 

  Passing a `t:Flagsmith.Configuration.t` or options with `:enable_local_evaluation`
  as `true` will start a local process for the given api key used, if one is not 
  started yet, which requires you to be running the `Flagsmith.Supervisor`.
  """
  @spec get_environment(Configuration.t() | Keyword.t()) ::
          {:ok, Schemas.Environment.t()} | {:error, term()}
  def get_environment_flags(configuration_or_env_or_opts \\ [])

  def get_environment_flags(%Configuration{enable_local_evaluation: local?} = config) do
    case local? do
      true -> Flagsmith.Client.Poller.get_environment_flags(config)
      false -> get_environment_flags_request(config)
    end
  end

  def get_environment_flags(%Schemas.Environment{} = env),
    do: {:ok, extract_flags(env)}

  def get_environment_flags(opts) when is_list(opts),
    do: get_environment_flags(new(opts))

  @doc false
  defp get_environment_flags_request(%Configuration{} = config) do
    case get_environment_request(config) do
      {:ok, %Schemas.Environment{} = env} ->
        {:ok, extract_flags(env)}

      error ->
        error
    end
  end

  @doc """
  Returns an `:ok` tuple containing a list of `t:Flagsmith.Schemas.Flag.t` structs,
  either from the local evaluation or API depending on the configuration used, or an
  `:error` tuple if unable to. The flags are retrieved based on a user identifier
  so take into account segments and traits. 

  Note: when using local evaluation there's no way to update the
  traits, the traits passed on to this function are used to check any segment rule
  specified on the `t:Flagsmith.Schemas.Environment.t` you're accessing. On the other
  hand, when using the live API evaluation the traits you pass will be used to update
  the traits associated with the identity you're specifying.

  Passing a `t:Flagsmith.Configuration.t` or options with `:enable_local_evaluation`
  as `true` will start a local process for the given api key used, if one is not 
  started yet, which requires you to be running the `Flagsmith.Supervisor`.
  """
  @spec get_identity_flags(
          Configuration.t() | Keyword.t(),
          String.t(),
          list(map() | Traits.Trait.t())
        ) ::
          {:ok, list(Schemas.Flag.t())} | {:error, term()}
  def get_identity_flags(configuration_or_env_or_opts \\ [], identifier, traits)

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

    case Tesla.get(http_client(config), @api_paths.identities, query: query) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        with %Schemas.Identity{flags: flags} <- Schemas.Identity.from_response(body),
             final_flags <- extract_flags(flags) do
          {:ok, final_flags}
        else
          error ->
            {:error, error}
        end

      error_resp ->
        return_error(error_resp)
    end
  end

  def analytics_track(configuration_or_env_or_opts \\ [], tracking)

  def analytics_track(opts, tracking)
      when is_list(opts) and is_map(tracking) and not is_struct(tracking),
      do: analytics_track(new(opts), tracking)

  def analytics_track(%Configuration{} = config, tracking) do
    case Tesla.post(http_client(config), @api_paths.analytics, tracking) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok, body}

      error_resp ->
        return_error(error_resp)
    end
  end

  defp build_identity_params(identifier, [_ | _] = traits) do
    [
      identifier: identifier,
      traits: Schemas.Traits.Trait.from(traits)
    ]
  end

  defp build_identity_params(identifier, _),
    do: [identifier: identifier]

  def extract_flags(%Schemas.Environment{} = env) do
    env
    |> Flagsmith.Engine.get_environment_feature_states()
    |> Enum.reduce(%{}, fn feature_state, acc ->
      %Schemas.Flag{feature_name: name} = flag = Schemas.Flag.from(feature_state)
      Map.put(acc, name, flag)
    end)
  end

  def extract_flags(feature_states) when is_list(feature_states) do
    Enum.reduce(feature_states, %{}, fn feature_state, acc ->
      %Schemas.Flag{feature_name: name} = flag = Schemas.Flag.from(feature_state)
      Map.put(acc, name, flag)
    end)
  end

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
