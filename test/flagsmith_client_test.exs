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
              %Schemas.Flags{
                flags: %{
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

      # with Schemas.Flags
      assert {:ok, %Schemas.Flags{} = flags_schema} = Flagsmith.Client.get_environment_flags(env)
      # the flags might have a different order because they come from a map that is
      # unordered, so we can't simply assert that it's the same with a ^ pin operator
      assert all_flags_2 = Flagsmith.Client.all_flags(flags_schema)

      # but we can by making sure it's the same size and each element is present in
      # the second list
      assert length(all_flags) == length(all_flags_2)

      assert Enum.all?(all_flags, fn flag ->
               assert Enum.any?(all_flags_2, fn flag_2 -> flag == flag_2 end)
             end)
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

      # with Schemas.Flags
      assert {:ok, %Schemas.Flags{} = flags} = Flagsmith.Client.get_environment_flags(env)

      assert Flagsmith.Client.is_feature_enabled(flags, "secret_button")
      refute Flagsmith.Client.is_feature_enabled(flags, "body_size")
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

      # with Schemas.Flags
      assert {:ok, %Schemas.Flags{} = flags} = Flagsmith.Client.get_environment_flags(env)

      assert ^flag = Flagsmith.Client.get_flag(flags, "secret_button")
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

      # with Schemas.Flags
      assert {:ok, %Schemas.Flags{} = flags} = Flagsmith.Client.get_environment_flags(env)

      assert ^value = Flagsmith.Client.get_feature_value(flags, "secret_button")
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

      # assert it works when using an Schemas.Environment

      assert %Schemas.Flag{feature_name: "test"} = Flagsmith.Client.get_flag(env, "doesnt_exist")

      assert "doesnt_exist" = Flagsmith.Client.get_feature_value(env, "doesnt_exist")

      assert Flagsmith.Client.is_feature_enabled(env, "doesnt_exist")

      # assert it works when using a Schemas.Flags
      assert {:ok, %Schemas.Flags{} = flags} = Flagsmith.Client.get_environment_flags(env)

      assert %Schemas.Flag{feature_name: "test"} =
               Flagsmith.Client.get_flag(flags, "doesnt_exist")

      assert "doesnt_exist" = Flagsmith.Client.get_feature_value(flags, "doesnt_exist")

      assert Flagsmith.Client.is_feature_enabled(flags, "doesnt_exist")
    end
  end

  describe "api calls for identity related" do
    test "get_identity_flags", %{config: config} do
      # set expectation for the http call 
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: "{\"transient\":false,\"identifier\":\"super1234324\"}",
          query: [],
          headers: [{@environment_header, config.environment_key}],
          url: Path.join([@api_url, @api_paths.identities]) <> "/",
          method: :post
        )

        {:ok, %Tesla.Env{status: 200, body: Test.Generators.map_identity()}}
      end)

      assert {
               :ok,
               %Schemas.Flags{
                 __configuration__: ^config,
                 flags: %{
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
               }
             } = Flagsmith.Client.get_identity_flags(config, "super1234324", [])

      # we also assert that no poller was initiated by making sure there's no pid
      assert :undefined = Flagsmith.Client.Poller.whereis(config.environment_key)
    end

    test "get_identity_flags for transient identity", %{config: config} do
      # set expectation for the http call
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: "{\"transient\":true,\"identifier\":\"super1234324\"}",
          query: [],
          headers: [{@environment_header, config.environment_key}],
          url: Path.join([@api_url, @api_paths.identities]) <> "/",
          method: :post
        )

        {:ok, %Tesla.Env{status: 200, body: Test.Generators.map_identity()}}
      end)

      Flagsmith.Client.get_identity_flags(config, "super1234324", [], true)
    end

    test "get_identity_flags for transient traits", %{config: config} do
      # set expectation for the http call
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body:
            "{\"transient\":false,\"identifier\":\"super1234324\",\"traits\":[{\"trait_key\":\"foo\",\"trait_value\":{\"value\":\"bar\",\"type\":\"string\"},\"transient\":false},{\"trait_key\":\"transient\",\"trait_value\":{\"value\":\"bar\",\"type\":\"string\"},\"transient\":true}]}",
          query: [],
          headers: [{@environment_header, config.environment_key}],
          url: Path.join([@api_url, @api_paths.identities]) <> "/",
          method: :post
        )

        {:ok, %Tesla.Env{status: 200, body: Test.Generators.map_identity()}}
      end)

      Flagsmith.Client.get_identity_flags(
        config,
        "super1234324",
        [
          %{trait_key: "foo", trait_value: "bar"},
          %{trait_key: "transient", trait_value: "bar", transient: true}
        ]
      )
    end
  end

  describe "failure tests" do
    test "get_environment", %{config: config} do
      # set expectation for the http call with :error tuple
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, config.environment_key}],
          url: Path.join([@api_url, @api_paths.environment]) <> "/",
          method: :get
        )

        {:error, :noop}
      end)

      assert {:error, :noop} = Flagsmith.Client.get_environment(config)

      # set expectation for the http call with :ok tuple, but 400 status
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, config.environment_key}],
          url: Path.join([@api_url, @api_paths.environment]) <> "/",
          method: :get
        )

        {:ok, %Tesla.Env{status: 400, body: "its_here"}}
      end)

      assert {:error, "its_here"} = Flagsmith.Client.get_environment(config)
    end

    test "get_flag with error", %{config: config} do
      # set expectation for the http call with :error tuple
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, config.environment_key}],
          url: Path.join([@api_url, @api_paths.environment]) <> "/",
          method: :get
        )

        {:error, :noop}
      end)

      assert {:error, :noop} = Flagsmith.Client.get_flag(config, "some_flag")

      # set expectation for the http call with :error tuple again
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, config.environment_key}],
          url: Path.join([@api_url, @api_paths.environment]) <> "/",
          method: :get
        )

        {:error, :noop}
      end)

      # now with default handler should return the flag instead of the error
      new_config = %{
        config
        | default_flag_handler: fn name -> %Schemas.Flag{feature_name: name} end
      }

      assert %Schemas.Flag{feature_name: "some_flag"} =
               Flagsmith.Client.get_flag(new_config, "some_flag")
    end
  end

  describe "User-Agent header" do
    test "user_agent/0 returns valid semver version" do
      user_agent = Flagsmith.Client.user_agent()
      version_part = String.replace_prefix(user_agent, "flagsmith-elixir-sdk/", "")

      assert {:ok, parsed} = Version.parse(version_part)
      assert is_integer(parsed.major) and parsed.major >= 0
      assert is_integer(parsed.minor) and parsed.minor >= 0
      assert is_integer(parsed.patch) and parsed.patch >= 0
    end

    test "HTTP client includes User-Agent header with valid semver", %{config: config} do
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        user_agent_header =
          Enum.find(tesla_env.headers, fn {header, _} ->
            header == "user-agent"
          end)

        assert user_agent_header != nil
        {_header, user_agent_value} = user_agent_header

        version_part = String.replace_prefix(user_agent_value, "flagsmith-elixir-sdk/", "")
        assert {:ok, _} = Version.parse(version_part)

        {:ok, %Tesla.Env{status: 200, body: Test.Generators.map_env()}}
      end)

      Flagsmith.Client.get_environment(config)
    end
  end
end
