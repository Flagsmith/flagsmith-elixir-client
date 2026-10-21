# Steps for the Flagsmith SDK behavioural spec: https://github.com/Flagsmith/sdk-spec
#
# Each function implements the Gherkin step in the comment above it.

defmodule SDKSpec.Steps do
  alias Flagsmith.Client

  defp as_spec_flags(flags) do
    for flag <- Client.all_flags(flags) do
      %{feature: flag.feature_name, enabled: flag.enabled, value: flag.value}
    end
  end

  # Given an SDK client for the environment
  def create_client(environment_key, api_url) do
    Client.new(environment_key: environment_key, api_url: api_url)
  end

  # When the application gets the environment flags
  def get_environment_flags(client) do
    with {:ok, flags} <- Client.get_environment_flags(client) do
      {:ok, as_spec_flags(flags)}
    end
  end

  # When the application gets the flags for identity "{identifier}" with traits:
  def get_identity_flags(client, identifier, traits) do
    traits = for {key, value} <- traits, do: %{trait_key: key, trait_value: value}

    with {:ok, flags} <- Client.get_identity_flags(client, identifier, traits) do
      {:ok, as_spec_flags(flags)}
    end
  end
end
