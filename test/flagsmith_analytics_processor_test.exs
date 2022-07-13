defmodule Flagsmith.Client.Analytics.Processor.Test do
  use ExUnit.Case, async: false

  import Mox, only: [verify_on_exit!: 1, expect: 3, allow: 3]
  import Flagsmith.Test.Helpers, only: [assert_request: 2]

  alias Flagsmith.Engine.Test
  alias Flagsmith.Schemas

  @environment_header Flagsmith.Configuration.environment_header()
  @api_url Flagsmith.Configuration.default_url()
  @api_paths Flagsmith.Configuration.api_paths()

  # setup Mox to verify any expectations
  setup :verify_on_exit!

  # we start the supervisor as a supervised process so it's shut down on every test
  # and subsequently shutting down the individual dynamic supervisor for the analytics
  # processor(s) which in turn will make the processor shutdown too
  setup do
    start_supervised!(Flagsmith.Supervisor)
    :ok
  end

  setup do
    [config: Flagsmith.Client.new(enable_analytics: true, environment_key: "test_key")]
  end

  # this test is outside because there's no expectations set
  test "dump is a no op when there's no tracking", %{config: config} do
    {:ok, pid} = Flagsmith.Client.Analytics.Processor.Supervisor.start_child(config)

    # assert that now there's a processor for the environment key we've been using
    ^pid = Flagsmith.Client.Analytics.Processor.whereis("test_key")
    assert is_pid(pid)

    # change the dump timeout
    assert :ok = :gen_statem.call(pid, {:update_dump_rate, 1})

    assert {:on,
            %Flagsmith.Client.Analytics.Processor{
              configuration: ^config,
              dump: 1,
              tracking: tracking
            }} = :sys.get_state(pid)

    assert tracking == %{}

    Process.sleep(5)
    # since the mock for the http adapter wasn't called we know it didn't try to
    # dump
    # we do a last alive? check after the 5milliseconds as a sanity check
    assert Process.alive?(pid)
  end

  describe "processor start and dump" do
    setup do
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

      # because we won't be using local evaluation the mock will be called by the
      # test process itself as part of the function call to get the environment,
      # so there's no need to set up mock allowances as was the case somewhere else

      :ok
    end

    test "doesn't start if enable_analytics is false", %{config: config} do
      config = %{config | enable_analytics: false}
      {:ok, environment} = Flagsmith.Client.get_environment(config)

      # get a flag from that environment
      assert %Schemas.Flag{feature_id: 17985, enabled: true} =
               Flagsmith.Client.get_flag(environment, "secret_button")

      # assert there's no processor after an environment request
      assert :undefined = Flagsmith.Client.Analytics.Processor.whereis("test_key")
    end

    test "doesn't start if no particular flag (or related functions) are called even with enable_analytics being set as true",
         %{
           config: config
         } do
      {:ok, _environment} = Flagsmith.Client.get_environment(config)

      # assert there's no processor after an environment request
      assert :undefined = Flagsmith.Client.Analytics.Processor.whereis("test_key")
    end

    test "starts if enable_analytics is true and queries for particular flags are done", %{
      config: config
    } do
      {:ok, environment} = Flagsmith.Client.get_environment(config)

      # get a flag from that environment
      feature_name_1 = "secret_button"
      assert %Schemas.Flag{enabled: true} =
               Flagsmith.Client.get_flag(environment, feature_name_1)

      # assert that now there's a processor for the environment key we've been using
      pid = Flagsmith.Client.Analytics.Processor.whereis("test_key")
      assert is_pid(pid)

      # assert it's tracking correctly:
      # - the tracking map should have 1 key being the name of the flag we retrieved
      # with the value being 1
      assert {:on,
              %Flagsmith.Client.Analytics.Processor{
                configuration: ^config,
                dump: 60_000,
                tracking: %{^feature_name_1 => 1} = tracking_map_1
              }} = :sys.get_state(pid)

      # assert there's only 1 key on the tracking map
      assert map_size(tracking_map_1) == 1

      # see if feature is enabled when using the client functions
      assert Flagsmith.Client.is_feature_enabled(environment, "secret_button")

      # assert that the processor is still alive and that now the tracking for
      # that feature name is at 2
      assert {:on,
              %Flagsmith.Client.Analytics.Processor{
                configuration: ^config,
                dump: 60_000,
                tracking: %{^feature_name_1 => 2} = tracking_map_2
              }} = :sys.get_state(pid)

      # assert there's still only 1 key on the tracking map
      assert map_size(tracking_map_2) == 1

      # assert other features track correctly too
      # get another flag from that environment
      feature_name_2 = "header_size"
      assert %Schemas.Flag{enabled: false} =
               Flagsmith.Client.get_flag(environment, feature_name_2)

      refute Flagsmith.Client.is_feature_enabled(environment, feature_name_2)

      # assert that the processor is still alive and that now the tracking for
      # the previous feature is still at 2, and for the new one, is at
      # 2 too
      assert {:on,
              %Flagsmith.Client.Analytics.Processor{
                configuration: ^config,
                dump: 60_000,
                tracking: %{^feature_name_1 => 2, ^feature_name_2 => 2} = tracking_map_3
              }} = :sys.get_state(pid)

      # assert there's now 2 keys on the tracking map
      assert map_size(tracking_map_3) == 2
    end

    test "dump is executed when there's items to track", %{config: config} do
      {:ok, pid} = Flagsmith.Client.Analytics.Processor.Supervisor.start_child(config)
      {:ok, environment} = Flagsmith.Client.get_environment(config)

      # assert that now there's a processor for the environment key we've been using
      ^pid = Flagsmith.Client.Analytics.Processor.whereis("test_key")
      assert is_pid(pid)

      # change the dump timeout
      assert :ok = :gen_statem.call(pid, {:update_dump_rate, 1})

      # use an example feature name that we know exists
      feature_name = "secret_button"

      # we need to set an additional expectation since it will call the analytics
      # endpoint

      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: "{\"#{feature_name}\":1}",
          query: [],
          headers: [{@environment_header, "test_key"}],
          url: Path.join([@api_url, @api_paths.analytics]) <> "/",
          method: :post
        )

        {:ok, %Tesla.Env{status: 200, body: %{}}}
      end)

      # but we need to allow the analytics processor process to be the one doing
      # the call
      allow(Tesla.Adapter.Mock, self(), pid)

      # afterwards the tracking map should be empty so it will not do any other
      # attempts to dump, meaning this inadvertently tests that after a dump the
      # tracking map is effectively empty

      assert Flagsmith.Client.is_feature_enabled(environment, feature_name)

      assert Flagsmith.Test.Helpers.wait_until(
               fn ->
                 {:on,
                  %Flagsmith.Client.Analytics.Processor{
                    configuration: ^config,
                    dump: 1,
                    tracking: tracking_map
                  }} = :sys.get_state(pid)

                 tracking_map == %{}
               end,
               15
             )
    end
  end
end
