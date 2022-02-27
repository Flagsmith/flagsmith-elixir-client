defmodule Flagsmith.Configuration do
  @default_url "https://api.flagsmith.com/api/v1"

  def get_environment_key(options \\ []) do
    case Keyword.get(options, :environment_key) do
      nil -> get!(:environment_key)
      key -> key
    end
  end

  def get_api_url(options \\ []) do
    case Keyword.get(options, :api_url) do
      nil ->
        case get(:api_url) do
          nil -> @default_url
          api_url when is_binary(api_url) -> api_url
        end

      api_url when is_binary(api_url) ->
        api_url
    end
  end

  defp get!(key) do
    Application.get_env(:flagsmith_engine, :configuration, [])
    |> Keyword.fetch!(key)
  end

  defp get(key) do
    Application.get_env(:flagsmith_engine, :configuration, [])
    |> Keyword.get(key)
  end
end
