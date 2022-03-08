defmodule Flagsmith.Client.Test do
  use ExUnit.Case

  import Mox, only: [verify_on_exit!: 1, expect: 3]
  import Flagsmith.Test.Helpers, only: [assert_request: 2]

  alias Flagsmith.Engine.Test

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

  describe "API calls" do
    test "get_environment_flags" do
      # set expectation for the http call 
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, "another_key"}],
          url: Path.join([@api_url, @api_paths.environment]) <> "/",
          method: :get
        )

        {:ok, %Tesla.Env{status: 200, body: Test.Generators.map_env()}}
      end)

      assert {:ok,
              %{
                "body_size" => %Flagsmith.Schemas.Flag{
                  enabled: false,
                  feature_id: 13535,
                  feature_name: "body_size",
                  value: "18px"
                },
                "header_size" => %Flagsmith.Schemas.Flag{
                  enabled: false,
                  feature_id: 13534,
                  feature_name: "header_size",
                  value: "24px"
                },
                "secret_button" => %Flagsmith.Schemas.Flag{
                  enabled: true,
                  feature_id: 17985,
                  feature_name: "secret_button",
                  value: "{\"colour\": \"#ababab\"}"
                },
                "test_identity" => %Flagsmith.Schemas.Flag{
                  enabled: true,
                  feature_id: 18382,
                  feature_name: "test_identity",
                  value: "very_yes"
                }
              }} = Flagsmith.Client.get_environment_flags(environment_key: "another_key")

      # we also assert that no poller was initiated by making sure there's no pid
      assert :undefined = Flagsmith.Client.Poller.whereis("another_key")
    end

    test "get_identity_flags" do
      # set expectation for the http call 
      expect(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
        assert_request(
          tesla_env,
          body: nil,
          query: [],
          headers: [{@environment_header, "another_key"}],
          url: Path.join([@api_url, @api_paths.identities]) <> "/",
          method: :get
        )

        {:ok, %Tesla.Env{status: 200, body: Test.Generators.map_identity()}}
      end)

      assert {
               :ok,
               %{}
             } =
               Flagsmith.Client.get_identity_flags(
                 [environment_key: "another_key"],
                 "test-identity",
                 []
               )
    end
  end
end
