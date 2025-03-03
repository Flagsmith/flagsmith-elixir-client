# FlagsmithEngine

Official Flagsmith Docs: [https://docs.flagsmith.com/clients/server-side](https://docs.flagsmith.com/clients/server-side)
Documentation on hexdocs: [https://hexdocs.pm/flagsmith_engine](https://hexdocs.pm/flagsmith_engine)


<div align="center">
     <a href="#installation">Installation</a><span>&nbsp; |</span>
     <a href="#usage">Usage</a><span>&nbsp; |</span>
     <a href="#analytics--local-evaluation">Analytics / Local Evaluation</a><span>&nbsp; |</span>
     <a href="#examples">Examples</a><span>&nbsp; |</span>
     <a href="#options">Options</a><span>&nbsp; |</span>
     <a href="#internals">Internals</a><span>&nbsp; |</span>
</div>

## Installation

The package can be installed by adding `flagsmith_engine` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:flagsmith_engine, "~> 1.0"}
  ]
end
```

## Usage

To use the Flagsmith Client library you need to provide a configuration, this can be done either when doing a request, or by setting it at the application level.

To configure it at the application level, add to the relevant config file (i.e.: `config/config.exs`):

```elixir
config :flagsmith_engine, :configuration,
       environment_key: "<YOUR SDK KEY>",
       api_url: "https://yourown_hosted_flagsmith.com/api/v1>",
       default_flag_handler: function_defaults_to_not_found,
       custom_headers: [{"to add to", "the requests"}],
       request_timeout_milliseconds: 5000,
       enable_local_evaluation: false,
       environment_refresh_interval_milliseconds: 60_000,
       retries: 0,
       enable_analytics: false
```

Any field `t:Flagsmith.Configuration.t/0` has can be set at the app level configuration.
When set at the app level you don't need to generate clients when using `Flagsmith.Client` module functions, unless you want or need different options.

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

## Analytics / Local Evaluation

To enable analytics or local evaluation, besides setting the configuration keys `enable_local_evaluation` and/or `enable_analytics` to true, you need to make sure `Flagsmith.Supervisor` is started before calling the client module, usually by placing it in your application supervision tree:

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

## Examples

###### remember all configuration options can be instead set at the application level but we keep them here so it's easier to understand how they interact

#### Get the value for multiple flags with a single API call

```elixir
# first get the overall environment

{:ok, %Flagsmith.Schemas.Environment{} = environment} = Flagsmith.Client.get_environment(environment_key: "MY_SDK_KEY")

# now query for what you care about with the environment

true = Flagsmith.Client.is_feature_enabled(environment, "my-feature-a")
false = Flagsmith.Client.is_feature_enabled(environment, "my-other-feature-b")

%Flagsmith.Schemas.Flag{
  enabled: false,
  feature_name: "body_size",
  feature_id: 1234,
  value: "18px"
} = Flagsmith.Client.get_flag(environment, "body_size")

:not_found = Flagsmith.Client.get_flag(environment, "non_existing_feature")
```

This would also work by getting a flags schema:

```elixir
{:ok, %Flagsmith.Schemas.Flags{} = flags} = Flagsmith.Client.get_environment_flags(environment_key: "MY_SDK_KEY")

true = Flagsmith.Client.is_feature_enabled(flags, "my-feature-a")
false = Flagsmith.Client.is_feature_enabled(flags, "my-other-feature-b")
```

#### Local Evaluation

If you have local evaluation enabled (remember to include the `Flagsmith.Supervisor` on your application supervision tree), then there's no need to worry about fetching the environment or flags to query - you can ask directly for the flag or if a feature is enabled, since the environment will be cached and automatically refreshed on given intervals, meaning there's no additional API calls:

```elixir
true = Flagsmith.Client.is_feature_enabled([environment_key: "MY_SDK_KEY", enable_local_evaluation: true], "my-feature-a")
false = Flagsmith.Client.is_feature_enabled([environment_key: "MY_SDK_KEY", enable_local_evaluation: true], "my-other-feature-b")

# if you configure your Flagsmith client at the application level, then you can do

true = Flagsmith.Client.is_feature_enabled("my-feature-a")
false = Flagsmith.Client.is_feature_enabled("my-other-feature-b")

"18px" = Flagsmith.Client.get_feature_value("title_font_size")
```

#### Analytics Tracking

When you enable analytics reporting, besides having to start the `Flagsmith.Supervisor` for it to work, you need to query for flags/features/features values through the exposed functions in `Flagsmith.Client.get_flag/2` `Flagsmith.Client.is_feature_enabled/2` and `Flagsmith.Client.get_feature_value/2`. This will update the tracking of the number of times they're accessed.

#### Identity & Traits

When using local evaluation with identity based requests the provided traits will not be updated on the Flagsmith platform, and to properly calculate the flags for an identity you need to provide any relevant trait as well. For instance, to get the `flags` for the identity `"user-a"` with a given trait:

```elixir
{:ok, flags} = Flagsmith.Client.get_identity_flags([environment_key: "MY_SDK_KEY", enable_local_evaluation: true], "user-a", [%{trait_key: "is_subscribed", trait_value: false}])

"true" = Flagsmith.Client.get_feature_value(flags, "show_subscription")
```

If you don't provide the trait, even if on the Flagsmith platform the identity has that trait, you will get the flags as if it didn't:

```elixir

{:ok, flags} = Flagsmith.Client.get_identity_flags([environment_key: "MY_SDK_KEY", enable_local_evaluation: true], "user-a", [])

"false" = Flagsmith.Client.get_feature_value(flags, "show_subscription")
```

When using normal API calls the same call would update the given trait and then return the flags taking into account that trait value as well.

```elixir
{:ok, flags} = Flagsmith.Client.get_identity_flags([environment_key: "MY_SDK_KEY"], "user-a", [%{trait_key: "is_subscribed", trait_value: false}])

"true" = Flagsmith.Client.get_feature_value(flags, "show_subscription")
```

And obviously, if the identity has that trait and you do the regular API call with no local evaluation, and without passing any trait in the query, you'll get the flags as expected from the Flagsmith platform:

```elixir
{:ok, flags} = Flagsmith.Client.get_identity_flags([environment_key: "MY_SDK_KEY"], "user-a", [])

"true" = Flagsmith.Client.get_feature_value(flags, "show_subscription")
```

## Options

- `environment_key` -> a server side sdk key (required)

- `api_url` -> the base url to which requests against the Flagsmith API will be made (defaults to: `"https://edge.api.flagsmith.com/api/v1"`)

- `default_flag_handler` -> a 1 arity function that receives a feature name (String.t()) and is called when calling feature related functions and the given feature isn't found or the API call fails -> defaults to returning `:not_found`

- `custom_headers` -> additional headers to include in the calls to the Flagsmith API, defaults to an empty list (no additional headers)

- `request_timeout_milliseconds` -> the timeout for the HTTP adapter when doing calls to the Flagsmith API (defaults to 5_000 milliseconds)

- `enable_local_evaluation` -> starts a poller cache for each sdk key in use, on their first invocation and keeps a local auto-refreshing cache with the environment document for each. This allows you to keep Flagsmith API calls to a minimum as the environment can be fetched locally and used for any other related functionality in the client.

- `environment_refresh_interval_milliseconds` -> the time to wait between polling the Flagsmith API for a new environment document, only relevant if `enable_local_evaluation` is set to true.

- `retries` -> the number of times the http adapter is allowed to retry failed calls to the Flagsmith API before deeming the response failed. Keep in mind that with local_evaluation and analytics, even if the requests fail after whatever number of retries you set here, they will keep being retried as their time-cycle resets (for the poller whatever is the environment_refresh_interval_milliseconds, for the analytics they're batched, and a dump is tried every 1 minute)

- `enable_analytics` -> track feature queries by reporting automatically to the Flagsmith API analytics endpoint queries and lookups to features. This only works when using the `Flagsmith.Client` module functions such as `is_feature_enabled`, `get_feature_value` and `get_flag`.
