defmodule Flagsmith.Configuration.Test do
  use ExUnit.Case, async: false

  # here we don't fetch it from the config, the purpose is to check if the
  # defaults and functions there use these, so in case some change happens
  # that the test breaks at least to bring to attention that these values were
  # expected and making sure it wasn't a mistake.
  # If we used those from the configuration as we do in other tests, then
  # we wouldn't be asserting much
  @default_url "https://api.flagsmith.com/api/v1"
  @environment_header "X-Environment-Key"
  @paths %{
    flags: "/flags/",
    identities: "/identities/",
    traits: "/traits/",
    analytics: "/analytics/flags/",
    environment: "/environment-document/"
  }

  alias Flagsmith.Configuration

  test "configuration requires env key" do
    assert_raise KeyError, ~r/key :environment_key not found in/, fn ->
      Configuration.build()
    end
  end

  test "configuration works if set at the application level" do
    Application.put_env(:flagsmith_engine, :configuration, environment_key: "A")

    assert %Configuration{
             environment_key: "A"
           } = Configuration.build()

    Application.delete_env(:flagsmith_engine, :configuration)
  end

  test "all defaults are applied" do
    assert %Configuration{
             environment_key: "A",
             api_url: @default_url,
             default_flag_handler: flag_handler,
             custom_headers: [],
             request_timeout_milliseconds: 5000,
             enable_local_evaluation: false,
             environment_refresh_interval_milliseconds: 60_000,
             retries: 0,
             enable_analytics: false
           } = Configuration.build(environment_key: "A")

    assert is_nil(flag_handler)
  end

  test "helper funs" do
    assert @default_url = Configuration.default_url()
    assert @environment_header = Configuration.environment_header()

    assert @paths = Configuration.api_paths()

    assert Enum.all?(@paths, fn {key, val} ->
             assert val == Configuration.api_paths(key)
           end)
  end

  test "options supercede application level config and app env supercedes defaults" do
    Application.put_env(:flagsmith_engine, :configuration,
      environment_key: "A",
      api_url: @default_url,
      default_flag_handler: fn x -> x end,
      custom_headers: [{"custom", "header"}, {"custom-2", "header"}],
      request_timeout_milliseconds: 10_000,
      enable_local_evaluation: true,
      environment_refresh_interval_milliseconds: 50_000,
      retries: 5,
      enable_analytics: true
    )

    assert %Configuration{
             environment_key: "B",
             api_url: @default_url,
             default_flag_handler: default_handler,
             custom_headers: [{"custom", "header"}, {"custom-2", "header"}],
             request_timeout_milliseconds: 10_000,
             enable_local_evaluation: true,
             environment_refresh_interval_milliseconds: 50_000,
             retries: 5,
             enable_analytics: true
           } = Configuration.build(environment_key: "B")

    assert is_function(default_handler, 1)
    assert default_handler.(true)

    Application.delete_env(:flagsmith_engine, :configuration)
  end
end
