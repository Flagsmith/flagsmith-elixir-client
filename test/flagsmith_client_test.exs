defmodule Flagsmith.Client.Test do
  use ExUnit.Case

  import Mox, only: [verify_on_exit!: 1, expect: 3]
  import Flagsmith.Test.Helpers, only: [assert_request: 2]

  alias Flagsmith.Engine.Test
  alias Flagsmith.Schemas

  @environment_header Flagsmith.Configuration.environment_header()
  @api_url Flagsmith.Configuration.default_url()
  @api_paths Flagsmith.Configuration.api_paths()

  # we start the supervisor as a supervised process so we can be sure that
  # the poller isn't started at all anyway (we need the registry to be up to
  # lookup the poller)
  setup do
    start_supervised!(Flagsmith.Supervisor)
    :ok
  end

  # setup Mox to verify any expectations 
  setup :verify_on_exit!

  setup do
    [config: Flagsmith.Client.new(environment_key: "client_test_key")]
  end

  describe "API calls except identity ones" do
    setup %{config: config} do
      # set expectation for the http call 
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, config.environment_key}],
          url: Path.join([@api_url, @api_paths.environment]) <> "/",
          method: :get
        )

        {:ok, %Tesla.Env{status: 200, body: Test.Generators.map_env()}}
      end)

      :ok
    end

    test "get_environment_flags", %{config: config} do
      assert {:ok,
              %{
                "body_size" => %Schemas.Flag{
                  enabled: false,
                  feature_id: 13535,
                  feature_name: "body_size",
                  value: "18px"
                },
                "header_size" => %Schemas.Flag{
                  enabled: false,
                  feature_id: 13534,
                  feature_name: "header_size",
                  value: "24px"
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
              }} = Flagsmith.Client.get_environment_flags(config)

      # we also assert that no poller was initiated by making sure there's no pid
      assert :undefined = Flagsmith.Client.Poller.whereis(config.environment_key)
    end

    test "all_flags", %{config: config} do
      assert {:ok, %Schemas.Environment{} = env} = Flagsmith.Client.get_environment(config)
      assert [_1, _2, _3, _4] = all_flags = Flagsmith.Client.all_flags(env)

      #  call with config will make a new http call
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, config.environment_key}],
          url: Path.join([@api_url, @api_paths.environment]) <> "/",
          method: :get
        )

        {:ok, %Tesla.Env{status: 200, body: Test.Generators.map_env()}}
      end)

      assert ^all_flags = Flagsmith.Client.all_flags(config)
    end

    test "is_feature_enabled", %{config: config} do
      assert {:ok, %Schemas.Environment{} = env} = Flagsmith.Client.get_environment(config)

      assert Flagsmith.Client.is_feature_enabled(env, "secret_button")
      refute Flagsmith.Client.is_feature_enabled(env, "body_size")

      #  call with config will make a new http call
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, config.environment_key}],
          url: Path.join([@api_url, @api_paths.environment]) <> "/",
          method: :get
        )

        {:ok, %Tesla.Env{status: 200, body: Test.Generators.map_env()}}
      end)

      assert Flagsmith.Client.is_feature_enabled(config, "secret_button")
    end

    test "get_flag", %{config: config} do
      assert {:ok, %Schemas.Environment{} = env} = Flagsmith.Client.get_environment(config)

      assert %Schemas.Flag{
               enabled: true,
               feature_id: 17985,
               feature_name: "secret_button",
               value: "{\"colour\": \"#ababab\"}"
             } = flag = Flagsmith.Client.get_flag(env, "secret_button")

      #  call with config will make a new http call
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, config.environment_key}],
          url: Path.join([@api_url, @api_paths.environment]) <> "/",
          method: :get
        )

        {:ok, %Tesla.Env{status: 200, body: Test.Generators.map_env()}}
      end)

      # assert it's exactly the same flag as when using the env
      assert ^flag = Flagsmith.Client.get_flag(config, "secret_button")
    end

    test "get_feature_value", %{config: config} do
      assert {:ok, %Schemas.Environment{} = env} = Flagsmith.Client.get_environment(config)

      assert "{\"colour\": \"#ababab\"}" =
               value = Flagsmith.Client.get_feature_value(env, "secret_button")

      #  call with config will make a new http call
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, config.environment_key}],
          url: Path.join([@api_url, @api_paths.environment]) <> "/",
          method: :get
        )

        {:ok, %Tesla.Env{status: 200, body: Test.Generators.map_env()}}
      end)

      # assert it's exactly the same value as when using the env
      assert ^value = Flagsmith.Client.get_feature_value(config, "secret_button")
    end

    test "get_flag, get_feature_value and is_feature_enabled with default_flag_handler", %{
      config: config
    } do
      new_config = %{
        config
        | default_flag_handler: fn feature_name ->
            %Schemas.Flag{feature_name: "test", enabled: true, value: feature_name}
          end
      }

      # set 3 additional expectations
      Enum.each(1..3, fn _ ->
        expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
          assert_request(
            tesla_env,
            body: nil,
            query: [],
            headers: [{@environment_header, config.environment_key}],
            url: Path.join([@api_url, @api_paths.environment]) <> "/",
            method: :get
          )

          {:ok, %Tesla.Env{status: 200, body: Test.Generators.map_env()}}
        end)
      end)

      assert {:ok, %Schemas.Environment{} = env} = Flagsmith.Client.get_environment(new_config)

      # assert it works when doing new "http calls"

      assert %Schemas.Flag{feature_name: "test"} =
               Flagsmith.Client.get_flag(new_config, "doesnt_exist")

      assert "doesnt_exist" = Flagsmith.Client.get_feature_value(new_config, "doesnt_exist")

      assert Flagsmith.Client.is_feature_enabled(new_config, "doesnt_exist")

      # assert it works when doing using an environment

      assert %Schemas.Flag{feature_name: "test"} = Flagsmith.Client.get_flag(env, "doesnt_exist")

      assert "doesnt_exist" = Flagsmith.Client.get_feature_value(env, "doesnt_exist")

      assert Flagsmith.Client.is_feature_enabled(env, "doesnt_exist")
    end
  end

  describe "api calls for identity related" do
    test "get_identity_flags", %{config: config} do
      # set expectation for the http call 
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, config.environment_key}],
          url: Path.join([@api_url, @api_paths.identities]) <> "/",
          method: :get
        )

        {:ok, %Tesla.Env{status: 200, body: Test.Generators.map_identity()}}
      end)

      assert {
               :ok,
               %{
                 "body_size" => %Schemas.Flag{
                   enabled: false,
                   feature_id: 13535,
                   feature_name: "body_size",
                   value: "18px"
                 },
                 "header_size" => %Schemas.Flag{
                   enabled: false,
                   feature_id: 13534,
                   feature_name: "header_size",
                   value: "34px"
                 },
                 "secret_button" => %Schemas.Flag{
                   enabled: true,
                   feature_id: 17985,
                   feature_name: "secret_button",
                   value: nil
                 },
                 "test_identity" => %Schemas.Flag{
                   enabled: true,
                   feature_id: 18382,
                   feature_name: "test_identity",
                   value: "very_no"
                 }
               }
             } = Flagsmith.Client.get_identity_flags(config, "super1234324", [])

      # we also assert that no poller was initiated by making sure there's no pid
      assert :undefined = Flagsmith.Client.Poller.whereis(config.environment_key)
    end
  end
end
