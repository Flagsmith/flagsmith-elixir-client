defmodule Flagsmith.Engine.Test.Generators do
  alias Flagsmith.Schemas.{Environment, Segments, Identity, Features, Traits}
  alias Flagsmith.Schemas.Traits.Trait.Value

  def json_env() do
    "{\"api_key\":\"cU3oztxgvRgZifpLepQJTX\",\"feature_states\":[{\"django_id\":72267,\"enabled\":false,\"feature\":{\"id\":13534,\"name\":\"header_size\",\"type\":\"MULTIVARIATE\"},\"feature_state_value\":\"24px\",\"featurestate_uuid\":\"16c5a45c-1d9c-4f44-bebe-5b73d60f897d\",\"multivariate_feature_state_values\":[{\"id\":2915,\"multivariate_feature_option\":{\"id\":849,\"value\":\"34px\"},\"mv_fs_value_uuid\":\"448a7777-91cf-47b0-bf16-a4d566ef7745\",\"percentage_allocation\":80.0}]},{\"django_id\":72269,\"enabled\":false,\"feature\":{\"id\":13535,\"name\":\"body_size\",\"type\":\"STANDARD\"},\"feature_state_value\":\"18px\",\"featurestate_uuid\":\"c3c61a9a-f153-46b2-8e9e-dd80d6529201\",\"multivariate_feature_state_values\":[]},{\"django_id\":92461,\"enabled\": true,\"feature\":{\"id\":17985,\"name\":\"secret_button\",\"type\":\"STANDARD\"},\"feature_state_value\":\"{\\\"colour\\\": \\\"#ababab\\\"}\",\"featurestate_uuid\":\"d6bbf961-1752-4548-97d1-02d60cc1ab44\",\"multivariate_feature_state_values\":[]},{\"django_id\":94235,\"enabled\":true,\"feature\":{\"id\":18382,\"name\":\"test_identity\",\"type\":\"STANDARD\"},\"feature_state_value\":\"very_yes\",\"featurestate_uuid\":\"aa1a4512-b1c7-44d3-a263-c21676852a52\",\"multivariate_feature_state_values\":[]}],\"id\":11278,\"project\":{\"hide_disabled_flags\":false,\"id\":4732,\"name\":\"testing-api\",\"organisation\":{\"feature_analytics\":false,\"id\":4131,\"name\":\"Mr. Bojangles Inc\",\"persist_trait_data\":true,\"stop_serving_flags\":false},\"segments\":[{\"feature_states\":[{\"django_id\":95632,\"enabled\":true,\"feature\":{\"id\":17985,\"name\":\"secret_button\",\"type\":\"STANDARD\"},\"feature_state_value\":\"\",\"featurestate_uuid\":\"3b58d149-fdb3-4815-b537-6583291523dd\",\"multivariate_feature_state_values\":[]}],\"id\":5241,\"name\":\"test_segment\",\"rules\":[{\"conditions\":[],\"rules\":[{\"conditions\":[{\"operator\":\"EQUAL\",\"property_\":\"show_popup\",\"value\":\"false\"}],\"rules\":[],\"type\":\"ANY\"}],\"type\":\"ALL\"}]},{\"feature_states\":[{\"django_id\":95631,\"enabled\":true,\"feature\":{\"id\":17985,\"name\":\"secret_button\",\"type\":\"STANDARD\"},\"feature_state_value\":\"\",\"featurestate_uuid\":\"adb486aa-563d-4b1d-9f72-bf5b210bf94f\",\"multivariate_feature_state_values\":[]}],\"id\":5243,\"name\":\"test_perc\",\"rules\":[{\"conditions\":[],\"rules\":[{\"conditions\":[{\"operator\":\"PERCENTAGE_SPLIT\",\"property_\":\"\",\"value\":\"50\"}],\"rules\":[],\"type\":\"ANY\"}],\"type\":\"ALL\"}]}]}}"
  end

  def map_env(), do: Jason.decode!(json_env())

  def full_env() do
    %Environment{
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
              percentage_allocation: 80.0
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
                        value: "50"
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
    }
  end

  def json_identity() do
    "{\"flags\":[{\"enabled\":false,\"environment\":11278,\"feature\":{\"created_date\":\"2021-10-24T13:40:02.805964Z\",\"default_enabled\":false,\"description\":\"Header Size\",\"id\":13534,\"initial_value\":\"24px\",\"name\":\"header_size\",\"type\":\"MULTIVARIATE\"},\"feature_segment\":null,\"feature_state_value\":\"34px\",\"id\":72267,\"identity\":null},{\"enabled\":false,\"environment\":11278,\"feature\":{\"created_date\":\"2021-10-24T13:41:35.650846Z\",\"default_enabled\":false,\"description\":null,\"id\":13535,\"initial_value\":\"18px\",\"name\":\"body_size\",\"type\":\"STANDARD\"},\"feature_segment\":null,\"feature_state_value\":\"18px\",\"id\":72269,\"identity\":null},{\"enabled\":true,\"environment\":11278,\"feature\":{\"created_date\":\"2022-02-07T19:54:48.630966Z\",\"default_enabled\":false,\"description\":null,\"id\":17985,\"initial_value\":null,\"name\":\"secret_button\",\"type\":\"STANDARD\"},\"feature_segment\":11493,\"feature_state_value\":\"\",\"id\":95631,\"identity\":null},{\"enabled\":true,\"environment\":11278,\"feature\":{\"created_date\":\"2022-02-13T16:14:18.546593Z\",\"default_enabled\":false,\"description\":null,\"id\":18382,\"initial_value\":\"very_yes\",\"name\":\"test_identity\",\"type\":\"STANDARD\"},\"feature_segment\":null,\"feature_state_value\":\"very_no\",\"id\":94429,\"identity\":24842744}],\"traits\":[]}"
  end

  def map_identity(), do: Jason.decode!(json_identity())

  def full_identity() do
    %Identity{
      flags: [
        %Features.FeatureState{
          enabled: false,
          environment: 11278,
          feature: %Features.Feature{
            created_date: ~U[2021-10-24 13:40:02Z],
            default_enabled: false,
            description: "Header Size",
            id: 13534,
            initial_value: "24px",
            name: "header_size",
            type: "MULTIVARIATE"
          },
          feature_segment: nil,
          feature_state_value: "34px",
          id: 72267,
          identity: nil
        },
        %Features.FeatureState{
          enabled: false,
          environment: 11278,
          feature: %Features.Feature{
            created_date: ~U[2021-10-24 13:41:35Z],
            default_enabled: false,
            description: nil,
            id: 13535,
            initial_value: "18px",
            name: "body_size",
            type: "STANDARD"
          },
          feature_segment: nil,
          feature_state_value: "18px",
          id: 72269,
          identity: nil
        },
        %Features.FeatureState{
          enabled: true,
          environment: 11278,
          feature: %Features.Feature{
            created_date: ~U[2022-02-07 19:54:48Z],
            default_enabled: false,
            description: nil,
            id: 17985,
            initial_value: nil,
            name: "secret_button",
            type: "STANDARD"
          },
          feature_segment: nil,
          feature_state_value: "{\"colour\": \"#ababab\"}",
          id: 92461,
          identity: nil
        },
        %Features.FeatureState{
          enabled: true,
          environment: 11278,
          feature: %Features.Feature{
            created_date: ~U[2022-02-13 16:14:18Z],
            default_enabled: false,
            description: nil,
            id: 18382,
            initial_value: "very_yes",
            name: "test_identity",
            type: "STANDARD"
          },
          feature_segment: nil,
          feature_state_value: "very_yes",
          id: 94235,
          identity: nil
        }
      ],
      identifier: nil,
      traits: [
        %Traits.Trait{
          id: 21_852_859,
          trait_key: "show_popup",
          trait_value: %Value{value: false, type: :boolean}
        }
      ]
    }
  end

  @default_opts %{
    value: "test value",
    description: "test description",
    environment: 1,
    segment: nil,
    identity: nil,
    type: "STANDARD",
    enabled: true,
    default_enabled: false
  }

  def full_feature_json(name, opts \\ @default_opts) do
    opts = Map.merge(@default_opts, opts)

    %{
      "enabled" => Map.get(opts, :enabled),
      "environment" => Map.get(opts, :environment),
      "feature_segment" => Map.get(opts, :segment),
      "feature_state_value" => Map.get(opts, :value),
      "id" => Flagsmith.Engine.Test.IDKeeper.get_and_update(),
      "identity" => Map.get(opts, :identity),
      "feature" => feature_json(name, opts)
    }
  end

  def feature_json(name, opts \\ @default_opts) do
    opts = Map.merge(@default_opts, opts)

    %{
      "name" => name,
      "created_date" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "default_enabled" => Map.get(opts, :default_enabled),
      "description" => Map.get(opts, :description),
      "initial_value" => Map.get(opts, :value),
      "type" => Map.get(opts, :type),
      "id" => Flagsmith.Engine.Test.IDKeeper.get_and_update()
    }
  end
end
