defmodule Flagsmith.Client.Poller.Test do
  use ExUnit.Case, async: false

  import Mox
  import Flagsmith.Test.Helpers, only: [assert_request: 2]

  alias Flagsmith.Engine.Test
  alias Flagsmith.Schemas

  @environment_header Flagsmith.Configuration.environment_header()
  @api_url Flagsmith.Configuration.default_url()
  @api_paths Flagsmith.Configuration.api_paths()

  # setup Mox to verify any expectations
  setup :verify_on_exit!

  # we start the supervisor as a supervised process so it's shut down on every test
  # and subsequently shutting down the individual dynamic supervisor for the poller(s)
  # which in turn will make the poller shutdown too
  setup do
    start_supervised!(Flagsmith.Supervisor)
    :ok
  end

  describe "poller init and refresh" do
    test "when started queries for the environment and doesn't query for following retrievals" do
      config =
        Flagsmith.Client.new(
          enable_local_evaluation: true,
          environment_key: "test_key"
        )

      # the map version of an environment document json string, we use this to return
      # it from the http adapter mock which is the same as the the adapter would do
      # with a json response coming from the api and automatically casting it to a map
      # since we use a middleware for json parsing and encoding on it
      env_response = Jason.decode!(Test.Generators.json_env())

      # create an expectation that the http adapter will be called for the given
      # path with proper headers set and answer with the proper environment document
      # map
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, "test_key"}],
          url: Path.join([@api_url, @api_paths.environment]) <> "/",
          method: :get
        )

        {:ok, %Tesla.Env{status: 200, body: env_response}}
      end)

      # we need to start the poller independently, so we're able to get the pid and
      # allow that pid to use the mock - in practice we can do directly
      # Flagsmith.Client.Poller.get_environment(...) and it will start it if needed
      # but that gives us back an environment and not a pid, so we wouldn't be able
      # to allow the mock to be called by this process since we wouldn't have a pid
      {:ok, pid} = Flagsmith.Client.Poller.start_link(config)

      # we allow the pid of the poller process to be the one calling the expectation
      allow(Tesla.Adapter.Mock, self(), pid)

      # we assert that we can get the environmnet from the poller
      # there's a case that could be made that we should perhaps only test
      # the calls directly from the Poller module, but by using the `local_evaluation`
      # config and then calling the Client module, we ensure that that is working
      # as expected too - the only real downside would be if we changed the client
      # interface but I don't see how that would happen without a significant change
      # to the logic, at which point, none of theses tests would be valid anymore,
      # so this way we cover that the client does delegate to the poller and all is
      # working as expected throughout
      {:ok, %Schemas.Environment{}} = Flagsmith.Client.get_environment(config)

      # we get the environment again to make sure the mock isn't called a 2nd time.
      # When the test exits if the mock was called more times than the number of
      # expectations we had set then it would not pass.
      # If the test passes then it means that the http adapter was called only the
      # 1 time we set as expected
      {:ok, %Schemas.Environment{}} = Flagsmith.Client.get_environment(config)

      # assert we can also get the feature flags
      {:ok,
       %Schemas.Flags{
         flags: %{
           "header_size" => %Schemas.Flag{
             enabled: false,
             feature_id: 13534,
             feature_name: "header_size",
             value: "24px"
           },
           "body_size" => %Schemas.Flag{
             enabled: false,
             feature_id: 13535,
             feature_name: "body_size",
             value: "18px"
           },
           "secret_button" => %Schemas.Flag{
             enabled: true,
             feature_id: 17985,
             feature_name: "secret_button",
             value: "{\"colour\": \"#ababab\"}"
           },
           "test_identity" => %Schemas.Flag{
             enabled: true,
             feature_id: 18382,
             feature_name: "test_identity",
             value: "very_yes"
           }
         }
       }} = Flagsmith.Client.get_environment_flags(config)
    end

    test "the refresh works accordingly" do
      # the configuration with a 3millisecond refresh interval
      # one seemed to be too low as very intermittently the test would fail in the
      # first `get_environment` or `get_environment_flags` because they poller would
      # have refreshed already, and no longer where there 4 flags
      config =
        Flagsmith.Client.new(
          enable_local_evaluation: true,
          environment_key: "test_key",
          environment_refresh_interval_milliseconds: 3
        )

      # the original env response
      env_response = Jason.decode!(Test.Generators.json_env())

      # create an expectation that the http adapter will be called for the given
      # path with proper headers set
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, "test_key"}],
          url: Path.join([@api_url, @api_paths.environment]) <> "/",
          method: :get
        )

        {:ok, %Tesla.Env{status: 200, body: env_response}}
      end)

      # this is the second expectation that should happen due to the refresh after 3
      # millisecond, because of that we should have another call to the env endpoint
      # almost immediately.
      # in this mock resolution we update the timer refresh rate in the poller to make
      # sure it's not called anymore and we answer with a different env, in order
      # to make sure the flags are different than originally set.
      # this is still a mock, so we can be sure due to the `verify_on_exit!` that it
      # will have to be called for the test to succeed
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, "test_key"}],
          url: Path.join([@api_url, @api_paths.environment]) <> "/",
          method: :get
        )

        poller_pid = Flagsmith.Client.Poller.whereis("test_key")
        :ok = :gen_statem.call(poller_pid, {:update_refresh_rate, 60_000})
        new_env_response = %{env_response | "feature_states" => []}

        {:ok, %Tesla.Env{status: 200, body: new_env_response}}
      end)

      # we start the poller independently, so we're able to get the pid and
      # allow that pid to use the mock
      # The problem is, the process that makes the refresh requests, in order to
      # keep the poller async and responsive at all times, is a spawned process
      # so its pid will not be the one from the poller and we don't know which pid
      # it will be, so after the initialization we set the VM to trace the poller
      # process proc related activity
      {:ok, pid} = Flagsmith.Client.Poller.start_link(config)

      # here we turn tracing to true for the poller pid, and events
      # related to procs (processes) so that we get tracing messages such as
      # processes being spawned by this pid - which will be the case with the
      # refresh retrieval processes
      :erlang.trace(pid, true, [:procs])

      # we allow the pid of the poller process to be the one calling the expectation
      # this will be for the initial call done by the poller itself
      allow(Tesla.Adapter.Mock, self(), pid)

      # we assert that we can get the environmnet from the poller and that it has 4
      # feature states
      {:ok, %Schemas.Environment{feature_states: [_1, _2, _3, _4]}} =
        Flagsmith.Client.get_environment(config)

      # we can also assert that it's 4 flags as well when asking directly for them
      {:ok,
       %Schemas.Flags{
         flags: %{
           "header_size" => _,
           "body_size" => _,
           "secret_button" => _,
           "test_identity" => _
         }
       }} = Flagsmith.Client.get_environment_flags(config)

      # now in order to allow the spawned process to be used to verify the mock
      # expectation we do a reduce, mimicking a loop, since we are expecting much
      # less than 100 trace events to come through, 100 is more than enough tries
      # to getting the one we care about - the spawning of the retrieval process
      #
      # what we do here is, since we have tracing for processes on the poller,
      # we wait until we receive a message saying our Poller (^pid) spawned a new
      # process, using a MFA (module function arguments tuple) for the function
      # `get_environment` in the Poller module, with the arguments being its own pid
      # and the config we have used when setting it up
      # since in that trace we have the pid of the newly spawned module, we can now
      # allow it to use the mock as well. We do that and stop the `reduce_while` with
      # `true` making the assertion pass
      #
      # all other trace messages (because there's plenty of them going on all the
      # the time from linking, exiting, tesla adaptor async stuff, etc
      # we just ignore and continue looping)
      #
      # if after 200 milliseconds on a reduction there's no message coming in we
      # bail the reduce with false which will make the assertion fail
      # We start the reduction with false, and return false from all continues because
      # in case we run out of iterations (100) we want the test to fail because it
      # means we didn't get our spawning message as expected and we won't be able
      # to set the allowance for the mock expectation
      assert Enum.reduce_while(1..100, false, fn _, _ ->
               receive do
                 {:trace, ^pid, :spawn, spawned_pid,
                  {Flagsmith.Client.Poller, :get_environment, [^pid, ^config]}} ->
                   allow(Tesla.Adapter.Mock, self(), spawned_pid)
                   {:halt, true}

                 _others ->
                   {:cont, false}
               after
                 200 ->
                   {:halt, false}
               end
             end)

      # we use wait_until to make sure the flags eventually change, within a max 15
      # millisecond window by calling the client for env flags with the same config
      # and checking if the flags are now an empty map
      assert Flagsmith.Test.Helpers.wait_until(
               fn ->
                 {:ok, %Schemas.Flags{flags: flags}} =
                   Flagsmith.Client.get_environment_flags(config)

                 flags == %{}
               end,
               15
             )

      # finally a sanity check that the poller is still the same pid, making sure
      # it wasn't blown out somewhere along the process and restarted itself
      # which could happen (and if it did it would call the 2nd mock itself on restart)
      # so we could, perhaps, not have a failing test but a bug in some part of
      # poller logic
      # the combination of knowing that:
      # 1 - there were flags on first request as set by the first mock
      # 2 - there were no flags on second request as set by the second mock
      # 3 - the poller never exited
      # 4 - the http adapter was called 2 times and no more
      # give us the guarantee that it's indeed working as expected in all fronts
      assert ^pid = Flagsmith.Client.Poller.whereis(config.environment_key)

      # this all may seem a bit too complex but don't forget though that this tests
      # actual runtime behaviour. There's no mocking as in most languages where
      # you basically just replace code by other code that has no bearing to actual
      # runtime dynamics nor concerns - here the code flow and runtime behaviour is
      # actually being exerted and asserted, the mocks are extremely explicit down
      # to the process that is calling them which is if not impossible, very hard
      # to even test in multithreaded code, here it's just verbose but very assertive
      # for instance if you take off the allowance we setup in the "loop" you'll see
      # the test fail
    end
  end

  # these tests are for the actual functionality of the poller API, so in this case
  # we're no longer caring about asserting all the other details as we did on
  # the previous describe (init & refresh).
  # Since that takes care of the inner workings of the poller now we just test
  # that the remaining functions exposed to the user work as expected, to ease
  # testing we actually start the poller from a setup block so we don't need to worry
  # about that in each test. The setup block isn't commented because those steps
  # can be read on the previous tests
  describe "poller requests" do
    setup do
      config =
        Flagsmith.Client.new(
          enable_local_evaluation: true,
          environment_key: "test_key"
        )

      env_response = Jason.decode!(Test.Generators.json_env())

      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, "test_key"}],
          url: Path.join([@api_url, @api_paths.environment]) <> "/",
          method: :get
        )

        {:ok, %Tesla.Env{status: 200, body: env_response}}
      end)

      # We stub the hashing module as well as that will be called for the identities
      # related retrievals
      stub_with(Flagsmith.Engine.MockHashing, Flagsmith.Engine.HashingUtils)

      {:ok, pid} = Flagsmith.Client.Poller.start_link(config)
      allow(Tesla.Adapter.Mock, self(), pid)

      # And because it will be done by the poller process we need to allow it to use
      # the stub as well
      allow(Flagsmith.Engine.MockHashing, self(), pid)

      # We return the pid to be available on the tests as a convenience we could do
      # start_link inside each test but this is equivalent since it runs on each test.
      #
      # We can then once again just make sure that the poller process never crashed
      # by asserting it's still the same pid after the test calls
      [poller_pid: pid, config: config]
    end

    test "get_identity_flags", %{poller_pid: pid, config: config} do
      # the default environment flags
      # we just fetch them and assert in order to make sure that the next following
      # assertions are by nature of passing identity/traits and not because they
      # were the environment values themselves
      assert {:ok,
              %Flagsmith.Schemas.Flags{
                __configuration__: %Flagsmith.Configuration{},
                flags: %{
                  "body_size" => %Flagsmith.Schemas.Flag{
                    enabled: false,
                    feature_name: "body_size",
                    value: "18px"
                  },
                  "header_size" => %Flagsmith.Schemas.Flag{
                    enabled: false,
                    feature_name: "header_size",
                    value: "24px"
                  },
                  "secret_button" => %Flagsmith.Schemas.Flag{
                    enabled: true,
                    feature_name: "secret_button",
                    value: "{\"colour\": \"#ababab\"}"
                  },
                  "test_identity" => %Flagsmith.Schemas.Flag{
                    enabled: true,
                    feature_name: "test_identity",
                    value: "very_yes"
                  }
                }
              }} = Flagsmith.Client.get_environment_flags(config)

      # secret_button should be overriden by the percentage segment because the hashing
      # of "testing" + segment is enough for the percentage of that segment to match
      # header_size should be overriden by multivariate again due to %
      assert {:ok,
              %Flagsmith.Schemas.Flags{
                __configuration__: %Flagsmith.Configuration{},
                flags: %{
                  "body_size" => %Flagsmith.Schemas.Flag{
                    enabled: false,
                    feature_name: "body_size",
                    value: "18px"
                  },
                  "header_size" => %Flagsmith.Schemas.Flag{
                    enabled: false,
                    feature_name: "header_size",
                    value: "34px"
                  },
                  "secret_button" => %Flagsmith.Schemas.Flag{
                    enabled: true,
                    feature_name: "secret_button",
                    value: nil
                  },
                  "test_identity" => %Flagsmith.Schemas.Flag{
                    enabled: true,
                    feature_name: "test_identity",
                    value: "very_yes"
                  }
                }
              }} = Flagsmith.Client.get_identity_flags(config, "8", [])

      # a different id that hashes both to higher than 60% in the multivariate part
      # and higher than 20% on the PERCENTAGE_SPLIT segment eval
      # this should render the header_size with the environment value and the same
      # for the secret_button
      assert {:ok,
              %Flagsmith.Schemas.Flags{
                __configuration__: %Flagsmith.Configuration{},
                flags: %{
                  "body_size" => %Flagsmith.Schemas.Flag{
                    enabled: false,
                    feature_name: "body_size",
                    value: "18px"
                  },
                  "header_size" => %Flagsmith.Schemas.Flag{
                    enabled: false,
                    feature_name: "header_size",
                    value: "24px"
                  },
                  "secret_button" => %Flagsmith.Schemas.Flag{
                    enabled: true,
                    feature_name: "secret_button",
                    value: "{\"colour\": \"#ababab\"}"
                  },
                  "test_identity" => %Flagsmith.Schemas.Flag{
                    enabled: true,
                    feature_name: "test_identity",
                    value: "very_yes"
                  }
                }
              }} = Flagsmith.Client.get_identity_flags(config, "atest12120", [])

      # the same id (meaning it should hash to the same things, but now passing a trait
      # results in a the secret_button being nil according to another segment rule
      # since the only thing that changes is providing traits to the function it
      # should assert that indeed traits affect the final resolution of the flags
      assert {:ok,
              %Flagsmith.Schemas.Flags{
                __configuration__: %Flagsmith.Configuration{},
                flags: %{
                  "body_size" => %Flagsmith.Schemas.Flag{
                    enabled: false,
                    feature_name: "body_size",
                    value: "18px"
                  },
                  "header_size" => %Flagsmith.Schemas.Flag{
                    enabled: false,
                    feature_name: "header_size",
                    value: "24px"
                  },
                  "secret_button" => %Flagsmith.Schemas.Flag{
                    enabled: true,
                    feature_name: "secret_button",
                    value: nil
                  },
                  "test_identity" => %Flagsmith.Schemas.Flag{
                    enabled: true,
                    feature_name: "test_identity",
                    value: "very_yes"
                  }
                }
              }} =
               Flagsmith.Client.get_identity_flags(config, "atest12120", [
                 %{trait_key: "show_popup", trait_value: false}
               ])

      # sanity check that nowhere did the poller process exit/crash
      assert ^pid = Flagsmith.Client.Poller.whereis(config.environment_key)
    end

    test "when a call to a poller that was started with a given configuration is given another configuration replace the __configuration__ in the returned environment",
         %{config: config} do
      new_config = Map.put(config, :enable_analytics, true)

      assert {:ok,
              %Flagsmith.Schemas.Environment{
                __configuration__: %Flagsmith.Configuration{enable_analytics: true}
              }} = Flagsmith.Client.get_environment(new_config)
    end

    test "when a call to a poller that was started with a given configuration is given another configuration replace the __configuration__ in the returned flags",
         %{config: config} do
      new_config = Map.put(config, :enable_analytics, true)

      assert {:ok,
              %Flagsmith.Schemas.Flags{
                __configuration__: %Flagsmith.Configuration{enable_analytics: true},
                flags: %{
                  "body_size" => %Flagsmith.Schemas.Flag{
                    enabled: false,
                    feature_name: "body_size",
                    value: "18px"
                  },
                  "header_size" => %Flagsmith.Schemas.Flag{
                    enabled: false,
                    feature_name: "header_size",
                    value: "24px"
                  },
                  "secret_button" => %Flagsmith.Schemas.Flag{
                    enabled: true,
                    feature_name: "secret_button",
                    value: "{\"colour\": \"#ababab\"}"
                  },
                  "test_identity" => %Flagsmith.Schemas.Flag{
                    enabled: true,
                    feature_name: "test_identity",
                    value: "very_yes"
                  }
                }
              }} = Flagsmith.Client.get_environment_flags(new_config)
    end
  end
end
