defmodule Flagsmith.Configuration.Test do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

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

  test "configuration validations" do
    assert_raise RuntimeError, ~r/environment_key needs to be/, fn ->
      Configuration.build(environment_key: true)
    end

    assert_raise RuntimeError, ~r/^api_url needs to be/, fn ->
      Configuration.build(environment_key: "A", api_url: 0)
    end

    assert_raise RuntimeError, ~r/^default_flag_handler needs/, fn ->
      Configuration.build(environment_key: "A", default_flag_handler: "oi")
    end

    Enum.each([0, [{1, 2, 3}], %{wrong: 1}], fn val ->
      assert_raise RuntimeError, ~r/^custom_headers needs to be/, fn ->
        Configuration.build(environment_key: "A", custom_headers: val)
      end
    end)

    Enum.each([0, 1000, "oi"], fn val ->
      assert_raise RuntimeError, ~r/^request_timeout_milliseconds needs to be/, fn ->
        Configuration.build(environment_key: "A", request_timeout_milliseconds: val)
      end
    end)

    assert_raise RuntimeError, ~r/^enable_local_evaluation needs to be/, fn ->
      Configuration.build(environment_key: "A", enable_local_evaluation: "true")
    end

    Enum.each([0, "oi"], fn val ->
      assert_raise RuntimeError, ~r/^environment_refresh_interval_milliseconds needs to be/, fn ->
        Configuration.build(environment_key: "A", environment_refresh_interval_milliseconds: val)
      end
    end)

    Enum.each([-1, "oi"], fn val ->
      assert_raise RuntimeError, ~r/^retries needs to be/, fn ->
        Configuration.build(environment_key: "A", retries: val)
      end
    end)

    assert_raise RuntimeError, ~r/^enable_analytics needs to be/, fn ->
      Configuration.build(environment_key: "A", enable_analytics: "false")
    end
  end

  test "logs warning if unknown opt is passed" do
    assert capture_log([level: :warn], fn ->
             Configuration.build(environment_key: "A", api_url_typo: "something")
           end) =~ "unknown option :api_url_typo passed as configuration to Flagsmith.Client"
  end
end
