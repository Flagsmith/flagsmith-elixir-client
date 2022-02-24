defmodule FlagsmithEngineTest do
  use ExUnit.Case, async: true

  alias Flagsmith.Schemas.Features

  # stub the mock so that it calls the normal module as it would under regular usage
  setup do
    Mox.stub_with(FlagsmithEngine.MockHashing, FlagsmithEngine.HashingUtils)
    :ok
  end

  #### NOTE ##
  #### These tests are more in-line with the python tests as they just test
  #### the functionality with a given environment instead of the poller

  test "parsing a json string into an environment struct" do
    assert {:ok, env_map} = Jason.decode(FlagsmithEngine.Test.Generators.json_env())

    assert {:ok,
            %Flagsmith.Schemas.Environment{
              amplitude_config: nil,
              api_key: "cU3oztxgvRgZifpLepQJTX",
              feature_states: [
                %Flagsmith.Schemas.Environment.FeatureState{
                  django_id: 72267,
                  enabled: false,
                  feature: %Flagsmith.Schemas.Environment.Feature{
                    id: 13534,
                    name: "header_size",
                    type: "MULTIVARIATE"
                  },
                  feature_state_value: "24px",
                  featurestate_uuid: "79f20ade-c211-48fd-9be7-b759079526ca",
                  multivariate_feature_state_values: [
                    %Flagsmith.Schemas.Environment.MultivariateFeatureStateValue{
                      id: 2915,
                      multivariate_feature_option:
                        %Flagsmith.Schemas.Environment.MultivariateFeatureOption{
                          id: 849,
                          value: "34px"
                        },
                      mv_fs_value_uuid: "d6ce29da-a737-45ec-a144-c95b1c64922b",
                      percentage_allocation: 80.0
                    }
                  ]
                },
                %Flagsmith.Schemas.Environment.FeatureState{
                  django_id: 72269,
                  enabled: false,
                  feature: %Flagsmith.Schemas.Environment.Feature{
                    id: 13535,
                    name: "body_size",
                    type: "STANDARD"
                  },
                  feature_state_value: "18px",
                  featurestate_uuid: "a1073731-f657-4348-8a39-e2bf1b5127a6",
                  multivariate_feature_state_values: []
                },
                %Flagsmith.Schemas.Environment.FeatureState{
                  django_id: 92461,
                  enabled: true,
                  feature: %Flagsmith.Schemas.Environment.Feature{
                    id: 17985,
                    name: "secret_button",
                    type: "STANDARD"
                  },
                  feature_state_value: "{\"colour\": \"#ababab\"}",
                  featurestate_uuid: "07cd43fb-405a-4c7a-8409-208f1739cda2",
                  multivariate_feature_state_values: []
                },
                %Flagsmith.Schemas.Environment.FeatureState{
                  django_id: 94235,
                  enabled: true,
                  feature: %Flagsmith.Schemas.Environment.Feature{
                    id: 18382,
                    name: "test_identity",
                    type: "STANDARD"
                  },
                  feature_state_value: "very_yes",
                  featurestate_uuid: "cfcedb16-47ab-4a48-97c6-46bfd0c6df69",
                  multivariate_feature_state_values: []
                }
              ],
              heap_config: nil,
              id: 11278,
              mixpanel_config: nil,
              project: %Flagsmith.Schemas.Environment.Project{
                hide_disabled_flags: false,
                id: 4732,
                name: "testing-api",
                organisation: %Flagsmith.Schemas.Environment.Organisation{
                  feature_analytics: false,
                  id: 4131,
                  name: "Mr. Bojangles Inc",
                  persist_trait_data: true,
                  stop_serving_flags: false
                },
                segments: [
                  %Flagsmith.Schemas.Segments.Segment{
                    feature_states: [
                      %Flagsmith.Schemas.Environment.FeatureState{
                        django_id: 95632,
                        enabled: false,
                        feature: %Flagsmith.Schemas.Environment.Feature{
                          id: 17985,
                          name: "secret_button",
                          type: "STANDARD"
                        },
                        feature_state_value: nil,
                        featurestate_uuid: "31d12712-2505-4555-a4f1-ea433feac701",
                        multivariate_feature_state_values: []
                      }
                    ],
                    id: 5241,
                    name: "test_segment",
                    rules: [
                      %Flagsmith.Schemas.Segments.Segment.Rule{
                        conditions: [],
                        rules: [
                          %Flagsmith.Schemas.Segments.Segment.Rule{
                            conditions: [
                              %Flagsmith.Schemas.Segments.Segment.Condition{
                                operator: :EQUAL,
                                property_: "show_popup",
                                value: "false"
                              }
                            ],
                            rules: [],
                            type: :ANY
                          }
                        ],
                        type: :ALL
                      }
                    ]
                  },
                  %Flagsmith.Schemas.Segments.Segment{
                    feature_states: [
                      %Flagsmith.Schemas.Environment.FeatureState{
                        django_id: 95631,
                        enabled: false,
                        feature: %Flagsmith.Schemas.Environment.Feature{
                          id: 17985,
                          name: "secret_button",
                          type: "STANDARD"
                        },
                        feature_state_value: nil,
                        featurestate_uuid: "82de5342-1a4d-438e-9a8f-6b6cb2c2404c",
                        multivariate_feature_state_values: []
                      }
                    ],
                    id: 5243,
                    name: "test_perc",
                    rules: [
                      %Flagsmith.Schemas.Segments.Segment.Rule{
                        conditions: [],
                        rules: [
                          %Flagsmith.Schemas.Segments.Segment.Rule{
                            conditions: [
                              %Flagsmith.Schemas.Segments.Segment.Condition{
                                operator: :PERCENTAGE_SPLIT,
                                property_: nil,
                                value: "30"
                              }
                            ],
                            rules: [],
                            type: :ANY
                          }
                        ],
                        type: :ALL
                      }
                    ]
                  }
                ]
              },
              segment_config: nil
            } = parsed} = FlagsmithEngine.parse_environment(env_map)

    assert env_map_2 = FlagsmithEngine.Test.Generators.json_env()
    assert {:ok, ^parsed} = FlagsmithEngine.parse_environment(env_map_2)
  end

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

  describe "segment <-> trait equality" do
    setup do
      [
        env: FlagsmithEngine.Test.Generators.full_env(),
        identity: FlagsmithEngine.Test.Generators.identities_list()
      ]
    end
  end
end
