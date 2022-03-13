# FlagsmithEngine

Documentation: [https://hexdocs.pm/flagsmith_engine](https://hexdocs.pm/flagsmith_engine)

<div align="center">
     <a href="#installation">Installation</a><span>&nbsp; |</span>
     <a href="#usage">Usage</a><span>&nbsp; |</span>
     <a href="#options">Options</a><span>&nbsp; |</span>
     <a href="#internals">Internals</a><span>&nbsp; |</span>
</div>

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `flagsmith_engine` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:flagsmith_engine, "~> 0.1.0"}
  ]
end
```

## Usage

You can configure this library by setting on the relevant config file:

```elixir
config :flagsmith_engine, :configuration,
       environment_key: "<YOUR SDK KEY>",
       api_url: "https://api.flagsmith.com/api/v1>",
       default_flag_handler: function_defaults_to_not_found,
       custom_headers: [{"to add to", "the requests"}],
       request_timeout_milliseconds: 5000,
       enabled_local_evaluation: false,
       environment_refresh_interval_milliseconds: 60_000,
       retries: 0,
       enable_analytics: false
```

Any field `t:Flagsmith.Configuration.t/0` has can be set at the app level configuration.
When set at the app level you don't need to generate clients when using `Flagsmith.Client` module functions, unless you want or need different options.

## Options

- `environment_key` -> a server side sdk key (required)

- `api_url` -> the base url to which requests against the Flagsmith API will be made (defaults to: "https://api.flagsmith.com/api/v1>")

- `default_flag_handler` -> a 1 arity function that receives a feature name (String.t()) and is called when calling feature related functions and the given feature isn't found -> defaults to returning `:not_found`

- `custom_headers` -> additional headers to include in the calls to the Flagsmith API, defaults to an empty list (no additional headers)

- `request_timeout_milliseconds` -> the timeout for the HTTP adapter when doing calls to the Flagsmith API (defaults to 5_000 milliseconds)

- `enable_local_evaluation` -> starts a poller cache for each sdk key in use, on their first invocation and keeps a local auto-refreshing cache with the environment document for each. This allows you to keep Flagsmith API calls to a minimum as the environment can be fetched locally and used for any other related functionality in the client.

- `environment_refresh_interval_milliseconds` -> the time to wait between polling the Flagsmith API for a new environment document, only relevant if `enable_local_evaluation` is set to true.

- `retries` -> the number of times the http adapter is allowed to retry failed calls to the Flagsmith API before deeming the response failed. Keep in mind that with local_evaluation and analytics, even if the requests fail after whatever number of retries you set here, they will keep being retried as their time-cycle resets (for the poller whatever is the environment_refresh_interval_milliseconds, for the analytics they're batched, and a dump is tried every 1 minute)

- `enable_analytics` -> track feature queries by reporting automatically to the Flagsmith API analytics endpoint queries and lookups to features. This only works when using the `Flagsmith.Client` module functions such as `is_feature_enabled`, `get_feature_value` and `get_flag`. 


To use the client library without application level configuration (or to override it) whenever a configuration is expected you can pass either a `t:Flagsmith.Configuration.t/0` struct or a keyword list with the options as elements. For instance:

```elixir
{:ok, environment} = Flagsmith.Client.get_environment(environment_key: "MY_SDK_KEY", enable_local_evaluation: true)
```

Or by passing a `t:Flagsmith.Configuration.t/0` to it:

```elixir
config = Flagsmith.Client.new(environment_key: "MY_SDK_KEY", enable_analytics: true, api_url: "https://my-own-api-endpoint.com")

{:ok, environment} = Flagsmith.Client.get_environment(config)
```

If you configured the `Flagsmith.Client` at the application level, with at least an `:environment_key`, you can simply call:

```elixir
{:ok, environment} = Flagsmith.Client.get_environment()
```

The precedence for the configuration values  is `Options > Application config > Defaults`.


To enable analytics or local evaluation, besides setting the configuration keys `enable_local_evaluation` and/or `enable_analytics`, you need to make sure `Flagsmith.Supervisor` is started before calling the client module, usually by placing it in your application supervision tree:

```elixir
defmodule YourAppWeb.Application do

   # ...
   
   def start(_type, _args) do
     children = [
       Flagsmith.Supervisor,
       # ... other stuff
     ]

     opts = [strategy: :one_for_one, name: YourAppWeb.Supervisor]
     Supervisor.start_link(children, opts)
   end
  
   # ...
```

If you only use API evaluation without tracking any analytics you don't need to to start the supervisor.