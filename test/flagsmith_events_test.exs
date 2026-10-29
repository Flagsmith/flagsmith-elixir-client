defmodule Flagsmith.Client.Events.Test do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox, only: [verify_on_exit!: 1, set_mox_global: 1, expect: 3, expect: 4]

  alias Flagsmith.Client
  alias Flagsmith.Client.Events.Processor
  alias Flagsmith.Schemas

  @environment_header Flagsmith.Configuration.environment_header()
  @api_url Flagsmith.Configuration.default_url()
  @api_paths Flagsmith.Configuration.api_paths()
  @events_url "https://events.example.com/"

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    start_supervised!(Flagsmith.Supervisor)

    [
      sdk_version: Client.version(),
      config:
        Client.new(
          environment_key: "events_test_key",
          enable_events: true,
          events_api_url: @events_url
        )
    ]
  end

  setup do
    test_pid = self()

    [
      receive_events: fn tesla_env, _options ->
        send(test_pid, {:events_request, tesla_env, Jason.decode!(tesla_env.body)})
        {:ok, %Tesla.Env{status: 202, body: ""}}
      end
    ]
  end

  describe "get_experiment_flag" do
    test "an identity in a running experiment is exposed to the variant it was served", %{
      config: config,
      sdk_version: sdk_version,
      receive_events: receive_events
    } do
      # Given
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert tesla_env.url == Path.join([@api_url, @api_paths.identities]) <> "/"

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "identifier" => "user_123",
             "traits" => [],
             "flags" => [
               %{
                 "feature" => %{"id" => 1, "name" => "banner", "type" => "STANDARD"},
                 "enabled" => true,
                 "feature_state_value" => "hello treatment",
                 "variant" => "treatment",
                 "metadata" => %{
                   "experiment" => %{
                     "id" => 7,
                     "name" => "banner experiment",
                     "in_experiment" => true
                   }
                 }
               }
             ]
           }
         }}
      end)

      expect(Tesla.Adapter.Mock, :call, receive_events)

      # When
      flag =
        Client.get_experiment_flag(config, "banner", "user_123", [
          %{trait_key: "plan", trait_value: "premium"}
        ])

      :ok = Processor.flush(config.environment_key)

      # Then
      assert %Schemas.Flag{
               feature_name: "banner",
               enabled: true,
               value: "hello treatment",
               variant: "treatment",
               experiment: %Schemas.Experiment{
                 id: 7,
                 name: "banner experiment",
                 in_experiment: true
               }
             } = flag

      assert_receive {:events_request, tesla_env, %{"events" => [event]}}
      assert tesla_env.method == :post
      assert tesla_env.url == @events_url <> "v1/events"
      assert {@environment_header, config.environment_key} in tesla_env.headers

      assert %{
               "event" => "$flag_exposure",
               "feature_name" => "banner",
               "identifier" => "user_123",
               "value" => "treatment",
               "traits" => %{"plan" => "premium"},
               "metadata" => %{"experiment_id" => 7, "sdk_version" => ^sdk_version},
               "timestamp" => timestamp
             } = event

      assert is_integer(timestamp)
    end

    for {case_name, flag_json, reason} <- [
          {"an identity outside a running experiment",
           %{"enabled" => true, "feature_state_value" => "hello"},
           "identity is not in a running experiment"},
          {"an identity not enrolled in a running experiment",
           %{
             "enabled" => true,
             "feature_state_value" => "hello",
             "metadata" => %{
               "experiment" => %{"id" => 7, "name" => "banner", "in_experiment" => false}
             }
           }, "identity is not in a running experiment"},
          {"an identity served no variant in a running experiment",
           %{
             "enabled" => true,
             "feature_state_value" => "hello",
             "metadata" => %{
               "experiment" => %{"id" => 7, "name" => "banner", "in_experiment" => true}
             }
           }, "flag has no variant"},
          {"an identity in a running experiment on a disabled feature",
           %{
             "enabled" => false,
             "feature_state_value" => "hello",
             "variant" => "treatment",
             "metadata" => %{
               "experiment" => %{"id" => 7, "name" => "banner", "in_experiment" => true}
             }
           }, "feature is disabled"}
        ] do
      test "#{case_name} is not exposed", %{config: config} do
        # Given
        flag_json =
          Map.put(unquote(Macro.escape(flag_json)), "feature", %{
            "id" => 1,
            "name" => "banner",
            "type" => "STANDARD"
          })

        expect(Tesla.Adapter.Mock, :call, fn _tesla_env, _options ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{"identifier" => "user_123", "traits" => [], "flags" => [flag_json]}
           }}
        end)

        # When
        log =
          capture_log([level: :debug], fn ->
            assert %Schemas.Flag{feature_name: "banner", value: "hello"} =
                     Client.get_experiment_flag(config, "banner", "user_123")
          end)

        # Then
        assert log =~ "Not sending $flag_exposure: #{unquote(reason)}"
        assert :undefined = Processor.whereis(config.environment_key)
      end
    end

    test "an identity is not exposed to a feature that does not exist", %{config: config} do
      # Given
      expect(Tesla.Adapter.Mock, :call, fn _tesla_env, _options ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{"identifier" => "user_123", "traits" => [], "flags" => []}
         }}
      end)

      # When
      log =
        capture_log([level: :debug], fn ->
          assert :not_found = Client.get_experiment_flag(config, "banner", "user_123")
        end)

      # Then
      assert log =~ "Not sending $flag_exposure: feature not found"
      assert :undefined = Processor.whereis(config.environment_key)
    end

    test "an experiment flag Flagsmith fails to evaluate is an error" do
      # Given
      expect(Tesla.Adapter.Mock, :call, fn _tesla_env, _options ->
        {:ok, %Tesla.Env{status: 500, body: "unavailable"}}
      end)

      # When / Then
      assert {:error, "unavailable"} =
               Client.get_experiment_flag(
                 [environment_key: "events_test_key", enable_events: true],
                 "banner",
                 "user_123"
               )
    end

    test "experiment flags require events to be enabled" do
      assert {:error, :events_disabled} =
               Client.get_experiment_flag([environment_key: "A"], "banner", "user_123")
    end
  end

  describe "track_event" do
    test "a tracked event reaches Flagsmith with its value, traits and metadata", %{
      config: config,
      sdk_version: sdk_version,
      receive_events: receive_events
    } do
      # Given
      expect(Tesla.Adapter.Mock, :call, receive_events)

      # When
      assert :ok =
               Client.track_event(config, "checkout_completed",
                 identifier: "user_123",
                 value: 42,
                 traits: [%{trait_key: "plan", trait_value: "premium"}],
                 metadata: %{"currency" => "GBP"}
               )

      :ok = Processor.flush(config.environment_key)

      # Then
      assert_receive {:events_request, _tesla_env, %{"events" => [event]}}

      assert %{
               "event" => "checkout_completed",
               "feature_name" => nil,
               "identifier" => "user_123",
               "value" => "42",
               "traits" => %{"plan" => "premium"},
               "metadata" => %{"currency" => "GBP", "sdk_version" => ^sdk_version}
             } = event
    end

    test "an event without value, traits or metadata reaches Flagsmith", %{
      sdk_version: sdk_version,
      receive_events: receive_events
    } do
      # Given
      expect(Tesla.Adapter.Mock, :call, receive_events)

      # When
      assert :ok =
               Client.track_event(
                 [environment_key: "events_test_key", enable_events: true],
                 "signed_up"
               )

      :ok = Processor.flush("events_test_key")

      # Then
      assert_receive {:events_request, _tesla_env, %{"events" => [event]}}

      assert %{
               "event" => "signed_up",
               "identifier" => nil,
               "value" => nil,
               "traits" => nil,
               "metadata" => %{"sdk_version" => ^sdk_version}
             } = event
    end

    test "event names reserved for Flagsmith are refused", %{config: config} do
      assert {:error, {:reserved_event_name, "$checkout"}} =
               Client.track_event(config, "$checkout", identifier: "user_123")

      assert :undefined = Processor.whereis(config.environment_key)
    end

    test "event values other than strings, numbers and booleans are refused", %{config: config} do
      assert {:error, {:invalid_value, %{"amount" => 42}}} =
               Client.track_event(config, "checkout_completed", value: %{"amount" => 42})

      assert :undefined = Processor.whereis(config.environment_key)
    end

    test "tracking events requires events to be enabled" do
      assert {:error, :events_disabled} =
               Client.track_event([environment_key: "A"], "checkout_completed")
    end
  end

  describe "track_exposure_event" do
    test "an exposure reaches Flagsmith as a $flag_exposure event", %{
      sdk_version: sdk_version,
      receive_events: receive_events
    } do
      # Given
      expect(Tesla.Adapter.Mock, :call, receive_events)

      # When
      assert :ok =
               Client.track_exposure_event(
                 [environment_key: "events_test_key", enable_events: true],
                 "banner",
                 identifier: "user_123",
                 value: true,
                 metadata: %{"experiment_id" => 1}
               )

      :ok = Processor.flush("events_test_key")

      # Then
      assert_receive {:events_request, _tesla_env, %{"events" => [event]}}

      assert %{
               "event" => "$flag_exposure",
               "feature_name" => "banner",
               "identifier" => "user_123",
               "value" => "true",
               "metadata" => %{"experiment_id" => 1, "sdk_version" => ^sdk_version}
             } = event
    end

    test "an identity exposed to the same variant twice before a flush is sent once", %{
      config: config,
      receive_events: receive_events
    } do
      # Given
      expect(Tesla.Adapter.Mock, :call, receive_events)

      # When
      log =
        capture_log([level: :debug], fn ->
          for value <- ["control", "control", "treatment"] do
            :ok =
              Client.track_exposure_event(config, "banner", identifier: "user_123", value: value)
          end

          :ok = Processor.flush(config.environment_key)
        end)

      # Then
      assert_receive {:events_request, _tesla_env, %{"events" => events}}
      assert ["control", "treatment"] = Enum.map(events, & &1["value"])
      assert log =~ "Skipping duplicate $flag_exposure event"
    end

    test "an exposure without an identifier is refused", %{config: config} do
      assert {:error, :identifier_required} =
               Client.track_exposure_event(config, "banner", value: "control")

      assert {:error, :identifier_required} =
               Client.track_exposure_event(config, "banner", identifier: "", value: "control")

      assert :undefined = Processor.whereis(config.environment_key)
    end

    test "tracking exposures requires events to be enabled" do
      assert {:error, :events_disabled} =
               Client.track_exposure_event([environment_key: "A"], "banner",
                 identifier: "user_123"
               )
    end
  end

  describe "sending events" do
    test "buffered events are sent on every flush interval", %{receive_events: receive_events} do
      # Given
      config =
        Client.new(
          environment_key: "events_test_key",
          enable_events: true,
          events_api_url: @events_url,
          events_flush_interval_milliseconds: 10
        )

      expect(Tesla.Adapter.Mock, :call, 2, receive_events)

      # When
      :ok = Client.track_event(config, "first")
      assert_receive {:events_request, _, %{"events" => [%{"event" => "first"}]}}, 500
      :ok = Client.track_event(config, "second")

      # Then
      assert_receive {:events_request, _, %{"events" => [%{"event" => "second"}]}}, 500
    end

    test "events Flagsmith fails to receive are sent again on the next flush", %{
      config: config,
      receive_events: receive_events
    } do
      # Given
      expect(Tesla.Adapter.Mock, :call, fn _tesla_env, _options ->
        {:ok, %Tesla.Env{status: 503, body: "unavailable"}}
      end)

      expect(Tesla.Adapter.Mock, :call, receive_events)
      :ok = Client.track_event(config, "checkout_completed", identifier: "user_123")

      # When
      log =
        capture_log(fn ->
          assert {:error, "unavailable"} = Processor.flush(config.environment_key)
        end)

      :ok = Client.track_event(config, "signed_out", identifier: "user_123")
      :ok = Processor.flush(config.environment_key)

      # Then
      assert log =~ "Failed to send events to Flagsmith, keeping them to retry"

      assert_receive {:events_request, _tesla_env, %{"events" => events}}
      assert ["checkout_completed", "signed_out"] = Enum.map(events, & &1["event"])
    end

    test "a full buffer of events is sent without waiting for the flush interval", %{
      config: config,
      receive_events: receive_events
    } do
      # Given
      expect(Tesla.Adapter.Mock, :call, receive_events)

      # When
      for n <- 1..1000, do: :ok = Client.track_event(config, "event_#{n}")

      # Then
      assert_receive {:events_request, _tesla_env, %{"events" => events}}, 1000
      assert length(events) == 1000
      assert :noop = Processor.flush(config.environment_key)
    end

    test "buffered events are sent when the application stops", %{
      config: config,
      receive_events: receive_events
    } do
      # Given
      expect(Tesla.Adapter.Mock, :call, receive_events)
      :ok = Client.track_event(config, "checkout_completed")

      # When
      :ok = stop_supervised(Flagsmith.Supervisor)

      # Then
      assert_receive {:events_request, _tesla_env, %{"events" => [event]}}
      assert %{"event" => "checkout_completed"} = event
    end

    test "nothing is sent when there are no events", %{config: config} do
      # Given
      expect(Tesla.Adapter.Mock, :call, fn _, _ -> {:ok, %Tesla.Env{status: 202}} end)
      :ok = Client.track_event(config, "checkout_completed")
      :ok = Processor.flush(config.environment_key)

      # When / Then
      assert :noop = Processor.flush(config.environment_key)
      assert :noop = Processor.flush("unused_environment_key")
    end
  end
end
