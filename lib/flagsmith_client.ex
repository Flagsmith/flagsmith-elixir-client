defmodule Flagsmith.Client do
  alias Flagsmith.Schemas
  alias Flagsmith.Configuration
  alias Flagsmith.Client.Analytics

  @flags_path "/flags/"
  @identities_path "/identities/"
  @traits_path "/traits/"
  @analytics_path "/analytics/flags/"

  @type tesla_header_list :: [{String.t(), String.t()}]

  def new(opts \\ []) do
    with environment_key <- Configuration.get_environment_key(opts),
         api_url <- Configuration.get_api_url(opts) do
      Tesla.client([
        base_url_middleware(api_url),
        auth_middleware(environment_key),
        Tesla.Middleware.JSON,
        {Tesla.Middleware.FollowRedirects, max_redirects: 5},
        {Tesla.Middleware.Timeout, timeout: 5_000}
      ])
    end
  end

  def get_flags(),
    do: get_flags(new(), nil)

  def get_flags(feature_name) when is_binary(feature_name),
    do: get_flags(new(), feature_name)

  def get_flags(%Tesla.Client{} = client, feature_name \\ nil) do
    params = if(feature_name, do: [query: %{feature: feature_name}], else: [])

    case Tesla.get(client, @flags_path, params) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok, Schemas.Features.FeatureState.from_response(body)}

      error_resp ->
        return_error(error_resp)
    end
  end

  def get_flags_for_user(identity) when is_binary(identity),
    do: get_flags_for_user(new(), identity, nil)

  def get_flags_for_user(identity, feature_name)
      when is_binary(identity) and is_binary(feature_name),
      do: get_flags_for_user(new(), identity, feature_name)

  # the feature_name query doesn't work
  def get_flags_for_user(%Tesla.Client{} = client, identity, feature_name \\ nil)
      when is_binary(identity) do
    params = [identifier: identity]
    params = if(feature_name, do: Keyword.put(params, :feature, feature_name), else: params)

    case Tesla.get(client, @identities_path, query: params) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok, Schemas.Identity.from_response(body)}

      error_resp ->
        return_error(error_resp)
    end
  end

  def get_value(feature_name) when is_binary(feature_name),
    do: get_value(new(), feature_name, nil)

  def get_value(feature_name, identity) when is_binary(feature_name) and is_binary(identity),
    do: get_value(new(), feature_name, identity)

  def get_value(%Tesla.Client{} = client, feature_name, identity \\ nil) do
    case identity do
      nil -> get_flags(client, feature_name)
      _ -> get_flags_for_user(client, identity, feature_name)
    end
    |> case do
      {:ok, %Schemas.Features.FeatureState{feature_state_value: val} = flag} ->
        Analytics.Processor.track(flag)
        {:ok, val}

      _ ->
        nil
    end
  end

  def get_trait(trait_key, identity) when is_binary(trait_key) and is_binary(identity),
    do: get_trait(new(), trait_key, identity)

  def get_trait(%Tesla.Client{} = client, trait_key, identity) do
    with {:ok, %{traits: traits}} <- get_flags_for_user(client, identity) do
      Schemas.Traits.Trait.extract_trait_value(trait_key, traits)
    else
      error -> error
    end
  end

  def set_trait(trait_key, trait_value, identity)
      when is_binary(trait_key) and is_binary(identity),
      do: set_trait(new(), trait_key, trait_value, identity)

  def set_trait(%Tesla.Client{} = client, trait_key, trait_value, identity)
      when is_binary(trait_key) and is_binary(identity) do
    params = %{
      identity: %{identifier: identity},
      trait_key: trait_key,
      trait_value: trait_value
    }

    case Tesla.post(client, @traits_path, params) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok, body}

      error_resp ->
        return_error(error_resp)
    end
  end

  def analytics_track(tracking) when is_map(tracking) and not is_struct(tracking),
    do: analytics_track(new(), tracking)

  def analytics_track(%Tesla.Client{} = client, tracking) do
    case Tesla.post(client, @analytics_path, tracking) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok, body}

      error_resp ->
        return_error(error_resp)
    end
  end

  def has_feature?(feature_name) when is_binary(feature_name),
    do: has_feature?(new(), feature_name)

  def has_feature?(%Tesla.Client{} = client, feature_name) when is_binary(feature_name) do
    with {:ok, %Schemas.Features.FeatureState{} = flag} <- get_flags(client, feature_name),
         _ <- Analytics.Processor.track(flag) do
      true
    else
      {:error, %{"detail" => _}} -> false
      error -> error
    end
  end

  def feature_enabled?(feature_name) when is_binary(feature_name),
    do: feature_enabled?(new(), feature_name, nil)

  def feature_enabled?(%Tesla.Client{} = client, feature_name) when is_binary(feature_name),
    do: feature_enabled?(client, feature_name, nil)

  def feature_enabled?(%Tesla.Client{} = client, feature_name, nil)
      when is_binary(feature_name) do
    with {:ok, %Schemas.Features.FeatureState{feature: feature} = flag} <-
           get_flags(client, feature_name),
         _ <- Analytics.Processor.track(flag) do
      feature && feature.enabled
    else
      {:error, %{"detail" => _}} -> false
      error -> error
    end
  end

  def feature_enabled?(%Tesla.Client{} = client, feature_name, identity)
      when is_binary(feature_name) and is_binary(identity) do
    with {:ok, %{flags: flags}} <- get_flags_for_user(client, identity) do
      case Enum.find(flags, fn %{feature: feature} -> feature.name == feature_name end) do
        nil ->
          {:error, :not_found}

        %Schemas.Features.FeatureState{enabled: enabled?} = flag ->
          Analytics.Processor.track(flag)
          enabled?
      end
    else
      error -> error
    end
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
  defp auth_header(environment_key), do: [{"X-Environment-Key", environment_key}]

  defp return_error({:ok, %{body: body} = resp}), do: IO.inspect(resp) && {:error, body}
  defp return_error({:error, _} = error), do: error
end
