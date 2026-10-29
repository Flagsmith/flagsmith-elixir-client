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
    # Events are sent by processes the Flagsmith supervisor runs.
    case Flagsmith.Supervisor.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    Client.new(
      environment_key: environment_key,
      api_url: api_url,
      enable_events: true,
      events_api_url: events_api_url
    )
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
end
