defmodule FlagsmithEngineTest do
  use ExUnit.Case, async: false

  alias Flagsmith.Schemas.Features

  #### NOTE ##
  #### This first set of tests are for the engine but using the poller arch
  #### the tests that replicate those in the python suite are afterwards and
  #### noted liked these

  import FlagsmithEngine.Test.Helpers, only: [ensure_no_poller: 1]
  import Mox, only: [verify_on_exit!: 1, expect: 3, allow: 3]

  # setup Mox to verify any expectations 
  setup :verify_on_exit!

  # we make sure the poller is not running at the beginning of any test if it is
  # we shut it down so that it no longer is and can start fresh when needed
  setup :ensure_no_poller

  test "returns the default base url" do
    assert "https://api.flagsmith.com/api/v1/" == FlagsmithEngine.api_url()
  end

  test "returns the url if set on the application env" do
    test_url = "https://test.com"

    Application.put_env(:flagsmith_engine, :api_url, test_url)

    assert test_url == FlagsmithEngine.api_url()

    Application.delete_env(:flagsmith_engine, :api_url)
  end

  describe "querying" do
    setup do
      # generate 4 json entries
      features_json =
        Enum.map(1..4, fn x ->
          FlagsmithEngine.Test.Generators.full_feature_json("feat#{x}", %{
            value: "val#{x}",
            description: "descript#{x}",
            identity: rem(x, 2)
          })
        end)

      # set expectation for the adapter and make the response be the list of
      # features as the json that would be given by the API
      expect(Tesla.Adapter.Mock, :call, fn _tesla_env, _options ->
        {:ok, %Tesla.Env{status: 200, body: features_json}}
      end)

      # Start the poller
      assert {:ok, pid} = FlagsmithEngine.Poller.start_link(api_key: "test")
      # Since it's the poller doing the http request (and it's a different process
      # than the one running the test), we need to explictly say that that process
      # is allowed to trigger the expectations set by this (self()) process
      allow(Tesla.Adapter.Mock, self(), pid)

      # ensure the statem is loaded and ready by doing a synchronous call
      assert {:loaded, _} = :sys.get_state(pid)

      [features: features_json]
    end

    test "querying by feature name", %{features: [feat_1 | _]} do
      name = feat_1["feature"]["name"]

      assert {
               :ok,
               %Flagsmith.API.FeatureStateSerializerFull{
                 feature: %Flagsmith.API.Feature{name: ^name}
               }
             } = FlagsmithEngine.get_feature(name)
    end

    test "querying a non existing feature by name returns error" do
      assert {:error, :not_found} = FlagsmithEngine.get_feature("non_existing")
    end

    test "querying by feature name with identity", %{features: [feat_1 | _]} do
      name = feat_1["feature"]["name"]
      identity = feat_1["identity"]

      assert {
               :ok,
               %Features.FeatureState{
                 feature: %Features.Feature{name: ^name}
               }
             } = FlagsmithEngine.get_feature(name, identity)
    end

    test "querying by feature name with wrong identity returns error", %{features: [feat_1 | _]} do
      name = feat_1["feature"]["name"]

      assert {:error, :not_found} = FlagsmithEngine.get_feature(name, 10_000)
    end

    test "get_flags", %{features: feats_json} do
      assert feats = FlagsmithEngine.get_features()
      assert is_list(feats) and length(feats) == length(feats_json)

      assert Enum.all?(feats_json, fn %{"id" => id, "feature" => %{"name" => name}} ->
               Enum.any?(feats, fn %{id: f_id, feature: %{name: f_name}} ->
                 f_id == id && f_name == name
               end)
             end)
    end

    test "get_flags with identity", %{features: [feat_1 | _] = feats_json} do
      assert identity = feat_1["identity"]

      only_identity =
        Enum.filter(feats_json, fn %{"identity" => id} ->
          id == identity
        end)

      # assert that there's at least some filtered feat, but also that the total is
      # less than the non-filtered total to make sure the expectations are correct
      # down the line
      assert length(only_identity) > 0 && length(only_identity) < length(feats_json)

      assert feats = FlagsmithEngine.get_features(identity)

      assert is_list(feats) and length(feats) == length(only_identity)

      assert Enum.all?(only_identity, fn %{"id" => id, "feature" => %{"name" => name}} ->
               Enum.any?(feats, fn %{id: f_id, feature: %{name: f_name}} ->
                 f_id == id && f_name == name
               end)
             end)
    end

    test "get_feature_value", %{features: [feat_1 | _]} do
      name = feat_1["feature"]["name"]
      value = feat_1["feature_state_value"]

      assert {:ok, ^value} = FlagsmithEngine.get_feature_value(name)
    end

    test "get_feature_value w/ identity", %{features: [feat_1 | _]} do
      name = feat_1["feature"]["name"]
      identity = feat_1["identity"]
      value = feat_1["feature_state_value"]

      assert {:ok, ^value} = FlagsmithEngine.get_feature_value(name, identity)
    end

    test "get_feature_value w/ wrong identity returns error", %{features: [feat_1 | _]} do
      name = feat_1["feature"]["name"]

      assert {:error, :not_found} = FlagsmithEngine.get_feature_value(name, 10_000)
    end
  end

  #### NOTE ##
  #### These tests are more in-line with the python tests as they just test
  #### the functionality with a given environment instead of the poller 

  describe "engine with environment" do
    setup do
      [env: FlagsmithEngine.Test.Generators.full_env()]
    end

    test "get_environment_feature_states/1 when project hide_disabled is false", %{
      env: %{feature_states: feature_states} = env
    } do
      assert length(feature_states) > 0
      # note for non elixir devs the ^ (pin) operator on the left side of a match (=)
      # forces the variable to be exactly the one that was pinned instead of doing
      # re-assignement, it would be equivalent to doing var == something
      assert ^feature_states = FlagsmithEngine.get_environment_feature_states(env)
    end

    test "get_environment_feature_states/1 when project hide_disabled is true", %{env: env} do
      new_env = %{env | project: %{env.project | hide_disabled_flags: true}}
      assert [] = FlagsmithEngine.get_environment_feature_states(new_env)
    end

    test "get_environment_feature_states/1 when project hide_disabled is true and some flag(s) are enabled",
         %{env: env} do
      [first_feature_state | rem] = env.feature_states
      new_first_feature_state = %{first_feature_state | enabled: true}
      new_feature_states = [new_first_feature_state | rem]

      new_env = %{
        env
        | project: %{env.project | hide_disabled_flags: true},
          feature_states: new_feature_states
      }

      assert [^new_first_feature_state] = FlagsmithEngine.get_environment_feature_states(new_env)
    end

    test "get_environment_feature_state/2", %{env: env} do
      [%{feature: %{name: name}} = first_feature_state | _] = env.feature_states

      assert ^first_feature_state = FlagsmithEngine.get_environment_feature_state(env, name)
    end
  end

  describe "engine identity environment" do
    setup do
      [
        env: FlagsmithEngine.Test.Generators.full_env(),
        identity: FlagsmithEngine.Test.Generators.identities_list()
      ]
    end

    test "get_identity_feature_states/3", %{env: env, identity: identity} do
      assert [
               %Features.FeatureState{
                 id: 72267,
                 enabled: false,
                 environment: 11278,
                 feature: %Features.Feature{
                   initial_value: "24px",
                   name: "header_size",
                   type: "MULTIVARIATE"
                 },
                 feature_segment: nil,
                 feature_state_value: "34px",
                 identity: nil
               },
               %Features.FeatureState{},
               %Features.FeatureState{},
               %Features.FeatureState{}
             ] = FlagsmithEngine.get_identity_feature_states(env, identity, [])
    end

    test "get_identity_feature_state/4", %{env: env, identity: identity} do
      assert %Features.FeatureState{
               id: 72267,
               enabled: false,
               environment: 11278,
               feature: %Features.Feature{
                 initial_value: "24px",
                 name: "header_size",
                 type: "MULTIVARIATE"
               },
               feature_segment: nil,
               feature_state_value: "34px",
               identity: nil
             } = FlagsmithEngine.get_identity_feature_state(env, identity, "header_size", [])
    end

    test "get_identity_feature_state/4 with non-existing feature", %{env: env, identity: identity} do
      assert nil == FlagsmithEngine.get_identity_feature_state(env, identity, "non_existing", [])
    end
  end
end
