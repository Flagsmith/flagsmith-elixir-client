# Steps for the Flagsmith SDK behavioural spec: https://github.com/Flagsmith/sdk-spec
#
# Each function implements the Gherkin step in the comment above it.

defmodule SDKSpec.Steps do
  alias Flagsmith.Client
  alias Flagsmith.Schemas

  defp as_spec_flag(flag),
    do: %{feature: flag.feature_name, enabled: flag.enabled, value: flag.value}

  defp as_spec_flags(flags), do: Enum.map(Client.all_flags(flags), &as_spec_flag/1)

  defp as_traits(traits),
    do: for({key, value} <- traits, do: %{trait_key: key, trait_value: value})

  # Create the SDK client
  def create_client(environment_key, api_url) do
    Client.new(environment_key: environment_key, api_url: api_url)
  end

  # Create the SDK client with events enabled
  def create_client_with_events(environment_key, api_url, events_api_url) do
    with :ok <- start_supervisor() do
      Client.new(
        environment_key: environment_key,
        api_url: api_url,
        enable_events: true,
        events_api_url: events_api_url
      )
    end
  end

  # Create the SDK client with local evaluation
  def create_client_with_local_evaluation(environment_key, api_url) do
    client =
      Client.new(
        environment_key: environment_key,
        api_url: api_url,
        enable_local_evaluation: true
      )

    with :ok <- start_supervisor(),
         {:ok, _environment} <- Client.get_environment(client) do
      {:ok, client}
    end
  end

  # Create the SDK client with local evaluation and events enabled
  def create_client_with_local_evaluation_and_events(environment_key, api_url, events_api_url) do
    client =
      Client.new(
        environment_key: environment_key,
        api_url: api_url,
        enable_local_evaluation: true,
        enable_events: true,
        events_api_url: events_api_url
      )

    with :ok <- start_supervisor(),
         {:ok, _environment} <- Client.get_environment(client) do
      {:ok, client}
    end
  end

  defp start_supervisor do
    case Flagsmith.Supervisor.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> error
    end
  end

  # When the application gets the environment flags
  def get_environment_flags(client) do
    with {:ok, flags} <- Client.get_environment_flags(client) do
      {:ok, as_spec_flags(flags)}
    end
  end

  # When the application gets the flags for identity "{identifier}" with traits:
  def get_identity_flags(client, identifier, traits) do
    with {:ok, flags} <- Client.get_identity_flags(client, identifier, as_traits(traits)) do
      {:ok, as_spec_flags(flags)}
    end
  end

  # When the application gets the experiment flag "{feature}" for identity "{identifier}" with traits:
  def get_experiment_flag(client, feature, identifier, traits) do
    case Client.get_experiment_flag(client, feature, identifier, as_traits(traits)) do
      %Schemas.Flag{} = flag -> {:ok, [as_spec_flag(flag)]}
      :not_found -> {:ok, []}
      error -> error
    end
  end

  # When the application tracks event "{event}" for identity "{identifier}" with value {value} and metadata:
  def track_event(client, event, identifier, value, metadata) do
    Client.track_event(client, event, identifier: identifier, value: value, metadata: metadata)
  end

  # When the application tracks an exposure of feature "{feature}" for identity "{identifier}" with value {value} and metadata:
  def track_exposure_event(client, feature, identifier, value, metadata) do
    Client.track_exposure_event(client, feature,
      identifier: identifier,
      value: value,
      metadata: metadata
    )
  end

  # When the application tracks events "event_{first}" to "event_{last}" for identity "{identifier}"
  def track_numbered_events(client, first, last, identifier) do
    Enum.each(first..last, fn number ->
      :ok = Client.track_event(client, "event_#{number}", identifier: identifier)
    end)
  end

  # When the application flushes events
  def flush_events(client) do
    Client.flush_events(client)
    :ok
  end

  # When the application closes the client with a timeout of {timeout} seconds
  def close_client(client, timeout) do
    Client.close(client, round(timeout * 1000))
    :ok
  end
end
