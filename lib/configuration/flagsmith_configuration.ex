defmodule Flagsmith.Configuration do
  @default_url "https://api.flagsmith.com/api/v1"
  @environment_header "X-Environment-Key"

  @api_paths %{
    flags: "/flags/",
    identities: "/identities/",
    traits: "/traits/",
    analytics: "/analytics/flags/",
    environment: "/environment-document/"
  }

  @enforce_keys [:environment_key]
  defstruct [
    :environment_key,
    :default_flag_handler,
    api_url: @default_url,
    custom_headers: [],
    request_timeout_milliseconds: 5000,
    enable_local_evaluation: false,
    environment_refresh_interval_milliseconds: 60_000,
    retries: 0,
    enable_analytics: false
  ]

  @default_keys [
    :api_url,
    :default_flag_handler,
    :custom_headers,
    :request_timeout_milliseconds,
    :enable_local_evaluation,
    :environment_refresh_interval_milliseconds,
    :retries,
    :enable_analytics
  ]

  @type t() :: %__MODULE__{
          environment_key: String.t(),
          default_flag_handler: function(),
          api_url: String.t(),
          custom_headers: list({String.t(), String.t()}),
          request_timeout_milliseconds: non_neg_integer(),
          enable_local_evaluation: boolean(),
          environment_refresh_interval_milliseconds: non_neg_integer(),
          retries: non_neg_integer(),
          enable_analytics: boolean()
        }

  @doc false
  def default_url(), do: @default_url

  @doc false
  def environment_header(), do: @environment_header

  @doc false
  @spec api_paths() :: map()
  def api_paths(), do: @api_paths

  @doc false
  @spec api_paths(what :: atom()) :: String.t() | no_return
  def api_paths(what), do: Map.fetch!(@api_paths, what)

  @doc false
  def build(opts \\ []) do
    with key <- get_environment_key(opts),
         config <- %__MODULE__{environment_key: key} do
      Enum.reduce(@default_keys, config, fn key, config_acc ->
        maybe_add_key(config_acc, key, opts)
      end)
    end
  end

  defp get_environment_key(opts) do
    case Keyword.get(opts, :environment_key) do
      nil -> get!(:environment_key)
      key -> key
    end
  end

  defp maybe_add_key(config_acc, key, opts) do
    case Keyword.get(opts, key) do
      nil ->
        case get(key) do
          nil -> config_acc
          val -> Map.put(config_acc, key, val)
        end

      val ->
        Map.put(config_acc, key, val)
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
