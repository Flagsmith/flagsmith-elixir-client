defmodule Flagsmith.EngineTest do
  use ExUnit.Case, async: true

  alias Flagsmith.Schemas.{Environment, Features, Segments, Traits}
  alias Flagsmith.Engine.Test

  # stub the mock so that it calls the normal module as it would under regular usage
  setup do
    Mox.stub_with(Flagsmith.Engine.MockHashing, Flagsmith.Engine.HashingUtils)
    :ok
  end

  #### NOTE ##
  #### These tests are more in-line with the python tests as they just test
  #### the functionality with a given environment instead of the poller

  test "parsing a json string into an environment struct" do
    assert {:ok, env_map} = Jason.decode(Test.Generators.json_env())

    assert {:ok,
            %Environment{
              __configuration__: nil,
              amplitude_config: nil,
              api_key: "cU3oztxgvRgZifpLepQJTX",
              feature_states: [
                %Environment.FeatureState{
                  django_id: 72267,
                  enabled: false,
                  feature: %Environment.Feature{
                    id: 13534,
                    name: "header_size",
                    type: "MULTIVARIATE"
                  },
                  feature_state_value: "24px",
                  featurestate_uuid: "16c5a45c-1d9c-4f44-bebe-5b73d60f897d",
                  multivariate_feature_state_values: [
                    %Environment.MultivariateFeatureStateValue{
                      id: 2915,
                      multivariate_feature_option: %Environment.MultivariateFeatureOption{
                        id: 849,
                        value: "34px"
                      },
                      mv_fs_value_uuid: "448a7777-91cf-47b0-bf16-a4d566ef7745",
                      percentage_allocation: 60.0
                    }
                  ]
                },
                %Environment.FeatureState{
                  django_id: 72269,
                  enabled: false,
                  feature: %Environment.Feature{
                    id: 13535,
                    name: "body_size",
                    type: "STANDARD"
                  },
                  feature_state_value: "18px",
                  featurestate_uuid: "c3c61a9a-f153-46b2-8e9e-dd80d6529201",
                  multivariate_feature_state_values: []
                },
                %Environment.FeatureState{
                  django_id: 92461,
                  enabled: true,
                  feature: %Environment.Feature{
                    id: 17985,
                    name: "secret_button",
                    type: "STANDARD"
                  },
                  feature_state_value: "{\"colour\": \"#ababab\"}",
                  featurestate_uuid: "d6bbf961-1752-4548-97d1-02d60cc1ab44",
                  multivariate_feature_state_values: []
                },
                %Environment.FeatureState{
                  django_id: 94235,
                  enabled: true,
                  feature: %Environment.Feature{
                    id: 18382,
                    name: "test_identity",
                    type: "STANDARD"
                  },
                  feature_state_value: "very_yes",
                  featurestate_uuid: "aa1a4512-b1c7-44d3-a263-c21676852a52",
                  multivariate_feature_state_values: []
                }
              ],
              heap_config: nil,
              id: 11278,
              mixpanel_config: nil,
              project: %Environment.Project{
                hide_disabled_flags: false,
                id: 4732,
                name: "testing-api",
                organisation: %Environment.Organisation{
                  feature_analytics: false,
                  id: 4131,
                  name: "Mr. Bojangles Inc",
                  persist_trait_data: true,
                  stop_serving_flags: false
                },
                segments: [
                  %Segments.Segment{
                    feature_states: [
                      %Environment.FeatureState{
                        django_id: 95632,
                        enabled: true,
                        feature: %Environment.Feature{
                          id: 17985,
                          name: "secret_button",
                          type: "STANDARD"
                        },
                        feature_state_value: nil,
                        featurestate_uuid: "3b58d149-fdb3-4815-b537-6583291523dd",
                        multivariate_feature_state_values: []
                      }
                    ],
                    id: 5241,
                    name: "test_segment",
                    rules: [
                      %Segments.Segment.Rule{
                        conditions: [],
                        rules: [
                          %Segments.Segment.Rule{
                            conditions: [
                              %Segments.Segment.Condition{
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
                  %Segments.Segment{
                    feature_states: [
                      %Environment.FeatureState{
                        django_id: 95631,
                        enabled: true,
                        feature: %Environment.Feature{
                          id: 17985,
                          name: "secret_button",
                          type: "STANDARD"
                        },
                        feature_state_value: nil,
                        featurestate_uuid: "adb486aa-563d-4b1d-9f72-bf5b210bf94f",
                        multivariate_feature_state_values: []
                      }
                    ],
                    id: 5243,
                    name: "test_perc",
                    rules: [
                      %Segments.Segment.Rule{
                        conditions: [],
                        rules: [
                          %Segments.Segment.Rule{
                            conditions: [
                              %Segments.Segment.Condition{
                                operator: :PERCENTAGE_SPLIT,
                                property_: nil,
                                value: "20"
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
            } = parsed} = Flagsmith.Engine.parse_environment(env_map)

    assert env_map_2 = Test.Generators.json_env()
    assert {:ok, ^parsed} = Flagsmith.Engine.parse_environment(env_map_2)
  end

  describe "engine with environment" do
    setup do
      [env: Test.Generators.full_env()]
    end

    test "get_environment_feature_states/1 when project hide_disabled is false", %{
      env: %{feature_states: [_, _, _, _] = feature_states} = env
    } do
      # note for non elixir devs the ^ (pin) operator on the left side of a match (=)
      # forces the variable to be exactly the one that was pinned instead of doing
      # re-assignement, it would be equivalent to doing var == something
      assert ^feature_states = Flagsmith.Engine.get_environment_feature_states(env)
    end

    test "get_environment_feature_states/1 when project hide_disabled is true", %{env: env} do
      new_env = %{env | project: %{env.project | hide_disabled_flags: true}}
      assert [_, _] = Flagsmith.Engine.get_environment_feature_states(new_env)
    end

    test "get_environment_feature_states/1 when project hide_disabled is true and some flag(s) are enabled",
         %{env: env} do
      # hide_disabled_flags for the env
      env = %{env | project: %{env.project | hide_disabled_flags: true}}

      assert [_, _] = Flagsmith.Engine.get_environment_feature_states(env)
      assert [%{enabled: false} = first_feature_state | rem] = env.feature_states
      new_first_feature_state = %{first_feature_state | enabled: true}
      new_feature_states = [new_first_feature_state | rem]

      # replace the feature states with the new one that should have an additional enabled one
      new_env = %{env | feature_states: new_feature_states}

      # we should have 3 enabled, the 2 enabled originally + the last one we enabled
      assert [^new_first_feature_state, _, _] =
               Flagsmith.Engine.get_environment_feature_states(new_env)
    end

    test "get_environment_feature_state/2", %{env: env} do
      [%{feature: %{name: name}} = first_feature_state | _] = env.feature_states

      assert ^first_feature_state = Flagsmith.Engine.get_environment_feature_state(env, name)
    end
  end

  describe "engine identity environment" do
    setup do
      [
        env: Test.Generators.full_env(),
        identity: Test.Generators.full_identity()
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
             ] = Flagsmith.Engine.get_identity_feature_states(env, identity, [])
    end

    test "get_identity_segments/3", %{env: env, identity: identity} do
      # the identity we're using has `show_popup` trait as false by default so
      # it should evaluate as this segment being for this identity when no traits
      # are passed
      assert [%Flagsmith.Schemas.Segments.IdentitySegment{id: 5241, name: "test_segment"}] =
               Flagsmith.Engine.get_identity_segments(env, identity, [])

      # passing the trait as `true` should make this segment no longer match since
      # the condition is `show_popup` to be false
      assert [] =
               Flagsmith.Engine.get_identity_segments(env, identity, [
                 %Traits.Trait{
                   trait_key: "show_popup",
                   trait_value: %Traits.Trait.Value{value: true, type: :boolean}
                 }
               ])

      # and passing the trait as `false` (as is the default) should make it match just
      # the same as initially
      assert [%Flagsmith.Schemas.Segments.IdentitySegment{id: 5241, name: "test_segment"}] =
               Flagsmith.Engine.get_identity_segments(env, identity, [
                 %Traits.Trait{
                   trait_key: "show_popup",
                   trait_value: %Traits.Trait.Value{value: false, type: :boolean}
                 }
               ])
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
             } = Flagsmith.Engine.get_identity_feature_state(env, identity, "header_size", [])
    end

    test "get_identity_feature_state/4 with non-existing feature", %{env: env, identity: identity} do
      assert nil == Flagsmith.Engine.get_identity_feature_state(env, identity, "non_existing", [])
    end
  end
end
