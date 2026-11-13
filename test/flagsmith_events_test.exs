defmodule Flagsmith.Client.Events.Test do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Flagsmith.Test.Helpers, only: [wait_until: 2]
  import Mox, only: [verify_on_exit!: 1, set_mox_global: 1, expect: 3, expect: 4, stub: 3]

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

  describe "get_experiment_flag with local evaluation" do
    setup do
      Mox.stub_with(Flagsmith.Engine.MockHashing, Flagsmith.Engine.HashingUtils)

      [
        local_config:
          Client.new(
            environment_key: "events_test_key",
            enable_local_evaluation: true,
            enable_events: true,
            events_api_url: @events_url
          )
      ]
    end

    for {case_name, rollout, allocation, variant, value} <- [
          {"to the variant it was served", 100.0, 100.0, "treatment", "new checkout"},
          {"to control when served no variant", 100.0, 0.0, "control", "control"}
        ] do
      test "an identity in a running experiment is exposed #{case_name}", %{
        local_config: config,
        receive_events: receive_events
      } do
        # Given
        expect(Tesla.Adapter.Mock, :call, fn _tesla_env, _options ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: experiment_environment(unquote(rollout), unquote(allocation))
           }}
        end)

        expect(Tesla.Adapter.Mock, :call, receive_events)

        # When
        flag =
          Client.get_experiment_flag(config, "checkout", "user_123", [
            %{trait_key: "plan", trait_value: "premium"}
          ])

        :ok = Client.flush_events(config)

        # Then
        assert %Schemas.Flag{
                 value: unquote(value),
                 variant: unquote(variant),
                 experiment: %Schemas.Experiment{id: 9, in_experiment: true}
               } = flag

        assert_receive {:events_request, _tesla_env, %{"events" => [event]}}

        assert %{
                 "event" => "$flag_exposure",
                 "feature_name" => "checkout",
                 "identifier" => "user_123",
                 "value" => unquote(variant),
                 "traits" => %{"plan" => "premium"},
                 "metadata" => %{"experiment_id" => 9}
               } = event
      end
    end

    test "an identity a running experiment does not enroll is not exposed", %{
      local_config: config
    } do
      # Given
      expect(Tesla.Adapter.Mock, :call, fn _tesla_env, _options ->
        {:ok, %Tesla.Env{status: 200, body: experiment_environment(0.0, 100.0)}}
      end)

      # When
      flag = Client.get_experiment_flag(config, "checkout", "user_123", [])

      # Then
      assert %Schemas.Flag{
               value: "control",
               experiment: %Schemas.Experiment{in_experiment: false}
             } = flag

      assert :noop = Client.flush_events(config)
    end
  end

  # An environment document with an experiment on feature "checkout", as Flagsmith
  # sends it: enrolled identities match the experiment's rollout segment, whose
  # override serves the "treatment" variant to `allocation`% of them.
  defp experiment_environment(rollout, allocation) do
    feature_state = fn id, allocation, in_experiment ->
      %{
        "feature" => %{"id" => 43, "name" => "checkout", "type" => "MULTIVARIATE"},
        "enabled" => true,
        "django_id" => id,
        "featurestate_uuid" => Ecto.UUID.generate(),
        "feature_state_value" => "control",
        "multivariate_feature_state_values" => [
          %{
            "multivariate_feature_option" => %{
              "id" => 9,
              "key" => "treatment",
              "value" => "new checkout"
            },
            "percentage_allocation" => allocation,
            "id" => id,
            "mv_fs_value_uuid" => Ecto.UUID.generate()
          }
        ],
        "metadata" => %{
          "experiment" => %{
            "id" => 9,
            "name" => "checkout experiment",
            "in_experiment" => in_experiment
          }
        }
      }
    end

    segment = %{
      "id" => 19,
      "name" => "experiment-9-rollout",
      "rules" => [
        %{
          "type" => "ALL",
          "rules" => [],
          "conditions" => [
            %{
              "operator" => "PERCENTAGE_SPLIT",
              "value" => to_string(rollout),
              "property_" => "$.identity.key"
            }
          ]
        }
      ],
      "feature_states" => [
        Map.put(feature_state.(62, allocation, true), "feature_segment", %{"priority" => 0})
      ]
    }

    Flagsmith.Engine.Test.Generators.map_env()
    |> Map.put("feature_states", [feature_state.(61, 0.0, false)])
    |> put_in(["project", "segments"], [segment])
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

    test "a batch is retried until the events API accepts it, giving up on each attempt after 3 seconds",
         %{config: config, receive_events: receive_events} do
      # Given
      test_pid = self()

      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        send(test_pid, {:attempt, tesla_env.opts[:adapter][:timeout]})
        {:ok, %Tesla.Env{status: 503, body: "unavailable"}}
      end)

      expect(Tesla.Adapter.Mock, :call, fn _tesla_env, _options -> {:error, :econnreset} end)
      expect(Tesla.Adapter.Mock, :call, receive_events)
      :ok = Client.track_event(config, "checkout", identifier: "user_123")

      # When
      log = capture_log(fn -> assert :ok = Client.flush_events(config) end)

      # Then
      assert_receive {:attempt, 3000}
      assert_receive {:events_request, _tesla_env, %{"events" => [%{"event" => "checkout"}]}}
      assert log =~ "attempt 1 of 3"
      assert log =~ "attempt 2 of 3"
      assert :noop = Client.flush_events(config)
    end

    test "a batch that keeps failing is sent with the next flush, ahead of events tracked since",
         %{config: config, receive_events: receive_events} do
      # Given
      expect(Tesla.Adapter.Mock, :call, 3, fn _tesla_env, _options ->
        {:ok, %Tesla.Env{status: 503, body: "unavailable"}}
      end)

      expect(Tesla.Adapter.Mock, :call, receive_events)
      :ok = Client.track_event(config, "add_to_cart", identifier: "user_123")

      log =
        capture_log(fn ->
          assert {:error, {:status, 503}} = Client.flush_events(config)
        end)

      # When
      :ok = Client.track_event(config, "checkout", identifier: "user_123")
      :ok = Client.flush_events(config)

      # Then
      assert log =~ "keeping them for the next flush"
      assert_receive {:events_request, _tesla_env, %{"events" => events}}
      assert ["add_to_cart", "checkout"] = Enum.map(events, & &1["event"])
    end

    for {case_name, failures} <- [
          {"a batch the events API rejects is dropped", [400]},
          {"a batch whose last attempt gets a server error is dropped", [503, 503, 500]}
        ] do
      test case_name, %{config: config, receive_events: receive_events} do
        # Given
        for status <- unquote(failures) do
          expect(Tesla.Adapter.Mock, :call, fn _tesla_env, _options ->
            {:ok, %Tesla.Env{status: status, body: "failed"}}
          end)
        end

        expect(Tesla.Adapter.Mock, :call, receive_events)
        :ok = Client.track_event(config, "add_to_cart", identifier: "user_123")

        log =
          capture_log(fn ->
            assert {:error, {:status, _}} = Client.flush_events(config)
          end)

        # When
        :ok = Client.track_event(config, "checkout", identifier: "user_123")
        :ok = Client.flush_events(config)

        # Then
        assert log =~ "dropping them"
        assert_receive {:events_request, _tesla_env, %{"events" => [%{"event" => "checkout"}]}}
      end
    end

    test "a batch whose last attempt fails otherwise is kept, after server errors", %{
      config: config,
      receive_events: receive_events
    } do
      # Given
      for status <- [500, 500, 503] do
        expect(Tesla.Adapter.Mock, :call, fn _tesla_env, _options ->
          {:ok, %Tesla.Env{status: status, body: "failed"}}
        end)
      end

      expect(Tesla.Adapter.Mock, :call, receive_events)
      :ok = Client.track_event(config, "add_to_cart", identifier: "user_123")
      capture_log(fn -> assert {:error, {:status, 503}} = Client.flush_events(config) end)

      # When
      :ok = Client.track_event(config, "checkout", identifier: "user_123")
      :ok = Client.flush_events(config)

      # Then
      assert_receive {:events_request, _tesla_env, %{"events" => events}}
      assert ["add_to_cart", "checkout"] = Enum.map(events, & &1["event"])
    end

    for status <- [401, 403] do
      test "an events API refusing the environment key with #{status} stops event tracking", %{
        config: config
      } do
        # Given
        expect(Tesla.Adapter.Mock, :call, fn _tesla_env, _options ->
          {:ok, %Tesla.Env{status: unquote(status), body: "refused"}}
        end)

        :ok = Client.track_event(config, "add_to_cart", identifier: "user_123")

        log =
          capture_log(fn ->
            assert {:error, {:status, unquote(status)}} = Client.flush_events(config)
          end)

        # When
        :ok = Client.track_event(config, "checkout", identifier: "user_123")

        # Then
        assert log =~ "stopping event tracking"
        assert :noop = Client.flush_events(config)
      end
    end

    test "a full buffer drops its oldest event", %{config: config, receive_events: receive_events} do
      # Given
      expect(Tesla.Adapter.Mock, :call, 3, fn _tesla_env, _options ->
        {:ok, %Tesla.Env{status: 503, body: "unavailable"}}
      end)

      expect(Tesla.Adapter.Mock, :call, receive_events)

      log =
        capture_log(fn ->
          for n <- 1..1000, do: :ok = Client.track_event(config, "event_#{n}")
          # Waits for, or finds done, the batch the full buffer sent by itself.
          assert Client.flush_events(config) in [:noop, {:error, {:status, 503}}]

          # When
          :ok = Client.track_event(config, "event_1001")
          :ok = Client.flush_events(config)
        end)

      # Then
      assert log =~ "dropping the oldest event_1 event"
      assert_receive {:events_request, _tesla_env, %{"events" => events}}
      assert Enum.map(events, & &1["event"]) == for(n <- 2..1001, do: "event_#{n}")
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
      assert Processor.flush(config.environment_key) in [:ok, :noop]
    end

    test "events tracked while a batch is being sent are buffered, up to the buffer's limit", %{
      config: config
    } do
      # Given a full buffer, whose batch the events API holds on to
      test_pid = self()

      stub(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        send(test_pid, {:holding, self(), Jason.decode!(tesla_env.body)})

        receive do
          :release -> {:ok, %Tesla.Env{status: 202, body: ""}}
        end
      end)

      for n <- 1..1000, do: :ok = Client.track_event(config, "event_#{n}")
      assert_receive {:holding, request, %{"events" => first_batch}}, 1000

      # When
      log =
        capture_log(fn ->
          for n <- 1001..2500, do: :ok = Client.track_event(config, "event_#{n}")

          # Then the processor keeps up, holding at most a full buffer besides the batch
          pid = Processor.whereis(config.environment_key)
          assert %Processor{buffered: 1000, sending: %{}} = :sys.get_state(pid)
          assert {:message_queue_len, 0} = Process.info(pid, :message_queue_len)
        end)

      assert log =~ "dropping the oldest event_1001 event"
      assert Enum.map(first_batch, & &1["event"]) == for(n <- 1..1000, do: "event_#{n}")

      # And the full buffer is sent once the batch is done with
      send(request, :release)
      assert_receive {:holding, request, %{"events" => second_batch}}, 1000
      send(request, :release)
      assert Enum.map(second_batch, & &1["event"]) == for(n <- 1501..2500, do: "event_#{n}")
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

    test "closing the client sends the buffered events, and stops sending events", %{
      config: config,
      receive_events: receive_events
    } do
      # Given
      expect(Tesla.Adapter.Mock, :call, fn _tesla_env, _options ->
        {:ok, %Tesla.Env{status: 503, body: "unavailable"}}
      end)

      expect(Tesla.Adapter.Mock, :call, receive_events)
      :ok = Client.track_event(config, "checkout", identifier: "user_123")

      # When
      capture_log(fn -> assert :ok = Client.close(config) end)

      # Then
      assert_receive {:events_request, _tesla_env, %{"events" => [%{"event" => "checkout"}]}}
      assert :undefined = Processor.whereis(config.environment_key)
    end

    test "closing the client returns within its timeout when the events API does not answer", %{
      config: config
    } do
      # Given
      test_pid = self()

      stub(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        timeout = tesla_env.opts[:adapter][:timeout]
        send(test_pid, {:attempt, timeout})
        Process.sleep(timeout)
        {:error, :timeout}
      end)

      :ok = Client.track_event(config, "checkout", identifier: "user_123")

      # When
      {elapsed, result} =
        :timer.tc(fn -> capture_log(fn -> send(test_pid, Client.close(config, 200)) end) end)

      # Then
      assert_received {:error, :timeout}
      assert_receive {:attempt, timeout} when timeout <= 200
      assert elapsed < 400_000
      assert is_binary(result)
    end

    test "a flush waits for one more batch at most while events keep being tracked", %{
      config: config
    } do
      # Given an events API holding on to each batch until released
      test_pid = self()

      stub(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        events = Enum.map(Jason.decode!(tesla_env.body)["events"], & &1["event"])
        send(test_pid, {:holding, self(), events})

        receive do
          :release -> {:ok, %Tesla.Env{status: 202, body: ""}}
        end
      end)

      flush = fn n ->
        spawn(fn -> send(test_pid, {:flushed, n, Client.flush_events(config)}) end)
      end

      :ok = Client.track_event(config, "first")
      pid = Processor.whereis(config.environment_key)
      flush.(1)
      assert_receive {:holding, request, ["first"]}

      # When a flush arrives while that batch is sent, with an event tracked since
      :ok = Client.track_event(config, "second")
      flush.(2)
      assert wait_until(fn -> :sys.get_state(pid).next_flush_waiters != [] end, 500)
      send(request, :release)

      # Then it waits for the batch in flight and one more, whatever is tracked meanwhile
      assert_receive {:flushed, 1, :ok}
      assert_receive {:holding, request, ["second"]}
      :ok = Client.track_event(config, "third")
      _ = :sys.get_state(pid)
      send(request, :release)
      assert_receive {:flushed, 2, :ok}
      refute_receive {:holding, _, _}, 100
    end

    test "an exposure dropped from a full buffer is tracked again", %{config: config} do
      # Given an exposure dropped from a buffer the events API failed to receive
      stub(Tesla.Adapter.Mock, :call, fn _tesla_env, _options ->
        {:ok, %Tesla.Env{status: 503, body: "unavailable"}}
      end)

      exposure = [identifier: "user_123", value: "treatment"]

      capture_log(fn ->
        :ok = Client.track_exposure_event(config, "banner", exposure)
        for n <- 2..1000, do: :ok = Client.track_event(config, "event_#{n}")
        assert Client.flush_events(config) in [:noop, {:error, {:status, 503}}]
        :ok = Client.track_event(config, "event_1001")
      end)

      # When
      pid = Processor.whereis(config.environment_key)

      {state, log} =
        with_log(fn ->
          :ok = Client.track_exposure_event(config, "banner", exposure)
          :sys.get_state(pid)
        end)

      # Then it's buffered again, the buffer dropping its oldest event for it
      assert log =~ "dropping the oldest event_2 event"
      events = :queue.to_list(state.buffer)
      assert ["event_3" | _] = Enum.map(events, & &1.event)
      assert %{event: "$flag_exposure", feature_name: "banner"} = List.last(events)
    end

    test "an exposure dropped when a kept batch no longer fits the buffer is tracked again", %{
      config: config
    } do
      # Given a batch with an exposure, held then failed by the events API, while the
      # buffer fills up with events tracked meanwhile
      test_pid = self()

      stub(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        events = Enum.map(Jason.decode!(tesla_env.body)["events"], & &1["event"])
        send(test_pid, {:holding, self(), events})

        receive do
          :release -> {:ok, %Tesla.Env{status: 503, body: "unavailable"}}
        end
      end)

      exposure = [identifier: "user_123", value: "treatment"]

      capture_log(fn ->
        :ok = Client.track_exposure_event(config, "banner", exposure)
        for n <- 2..1000, do: :ok = Client.track_event(config, "event_#{n}")
        for n <- 1001..2000, do: :ok = Client.track_event(config, "event_#{n}")

        for _attempt <- 1..3 do
          assert_receive {:holding, request, ["$flag_exposure" | _]}, 1000
          send(request, :release)
        end

        # The batch is kept, but only the newest 1000 events fit the buffer, which the
        # events tracked meanwhile filled up: they're sent straight away.
        assert_receive {:holding, _request, ["event_1001" | _]}, 1000
      end)

      # When
      :ok = Client.track_exposure_event(config, "banner", exposure)

      # Then
      pid = Processor.whereis(config.environment_key)

      assert [%{event: "$flag_exposure", feature_name: "banner"}] =
               :queue.to_list(:sys.get_state(pid).buffer)
    end

    test "closing the client stops a flush still sending when its timeout expires", %{
      config: config
    } do
      # Given a flush already sending, which the events API keeps failing slowly
      test_pid = self()

      stub(Tesla.Adapter.Mock, :call, fn _tesla_env, _options ->
        send(test_pid, :attempt)
        Process.sleep(100)
        {:ok, %Tesla.Env{status: 503, body: "unavailable"}}
      end)

      :ok = Client.track_event(config, "checkout", identifier: "user_123")
      pid = Processor.whereis(config.environment_key)
      monitor = Process.monitor(pid)
      spawn(fn -> send(test_pid, {:flushed, Processor.flush(config.environment_key)}) end)
      assert_receive :attempt

      # When
      log = capture_log(fn -> assert {:error, :timeout} = Client.close(config, 50) end)

      # Then the flush caller is told, rather than exiting, and nothing more is sent
      assert log =~ "Gave up sending events after 50 milliseconds while closing"
      assert_receive {:flushed, {:error, :closed}}
      assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
      refute_receive :attempt, 500
    end

    test "closing the client while it's already closing is a no-op", %{config: config} do
      # Given a close waiting on the events API
      test_pid = self()

      stub(Tesla.Adapter.Mock, :call, fn _tesla_env, _options ->
        send(test_pid, {:holding, self()})

        receive do
          :release -> {:ok, %Tesla.Env{status: 202, body: ""}}
        end
      end)

      :ok = Client.track_event(config, "checkout", identifier: "user_123")
      spawn(fn -> send(test_pid, {:closed, Client.close(config)}) end)
      assert_receive {:holding, request}

      # When / Then
      assert :noop = Client.close(config)
      send(request, :release)
      assert_receive {:closed, :ok}
    end

    test "flushing events after the processor has stopped is a no-op", %{config: config} do
      # Given
      expect(Tesla.Adapter.Mock, :call, fn _, _ -> {:ok, %Tesla.Env{status: 202}} end)
      :ok = Client.track_event(config, "checkout", identifier: "user_123")
      :ok = Client.close(config)

      # When / Then
      assert :noop = Client.flush_events(config)
    end

    test "flushing events requires events to be enabled" do
      assert {:error, :events_disabled} = Client.flush_events(environment_key: "A")
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
