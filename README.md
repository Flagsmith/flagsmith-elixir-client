# FlagsmithEngine

Documentation: [https://hexdocs.pm/flagsmith_engine](https://hexdocs.pm/flagsmith_engine)

<div align="center">
     <a href="#installation">Installation</a><span>&nbsp; |</span>
     <a href="#usage">Usage</a><span>&nbsp; |</span>
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
       api_url: "<defaults to: https://api.flagsmith.com/api/v1>",
       default_flag_handler: function_defaults_to_,
       custom_headers: [{"to add to", "the requests"}],
       request_timeout_milliseconds: 5000,
       enabled_local_evaluation: false,
       environment_refresh_interval_milliseconds: 60_000,
       retries: 0,
       enable_analytics: false
```

Any field `t:Flagsmith.Configuration.t/0` has can be set at the app level configuration.
When set at the app level you don't need to generate clients when using `Flagsmith.Client` module functions, unless you want or need different options.

When interacting with the functions in the client module whenever a configuration is expected you can pass either a `t:Flagsmith.Configuration.t/0` struct or a keyword list with the options as elements.

If any of analytics or local evaluation is enabled or wanted at some point, you need to make sure `Flagsmith.Supervisor` is started before calling the client module, usually by placing it in your application supervision tree:

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

If you only use API evaluation without tracking any analytics you don't need to change anything.


.... WIP
