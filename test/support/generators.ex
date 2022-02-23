defmodule FlagsmithEngine.Test.Generators do
  alias Flagsmith.Schemas.{Environment, Segments, Identity, Features, Traits}

  def full_env() do
    %Environment{
      id: 11278,
      api_key: "cU3oztxgvRgZifpLepQJTX",
      amplitude_config: nil,
      segment_config: nil,
      heap_config: nil,
      mixpanel_config: nil,
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
          featurestate_uuid: "d8cce15f-cf87-495a-902d-f989345d3e0c",
          multivariate_feature_state_values: [
            %Environment.MultivariateFeatureStateValue{
              id: 2915,
              multivariate_feature_option: %Environment.MultivariateFeatureOption{
                id: 849,
                value: "34px"
              },
              mv_fs_value_uuid: "4086b049-4bfe-459a-9282-ced14ebd26ad",
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
          featurestate_uuid: "15849151-6fce-4140-8972-061126767cd7",
          multivariate_feature_state_values: []
        },
        %Environment.FeatureState{
          django_id: 92461,
          enabled: false,
          feature: %Environment.Feature{
            id: 17985,
            name: "secret_button",
            type: "STANDARD"
          },
          feature_state_value: "{\"colour\": \"#ababab\"}",
          featurestate_uuid: "09ac9448-5053-4429-bd0d-7738e42dbfaf",
          multivariate_feature_state_values: []
        },
        %Environment.FeatureState{
          django_id: 94235,
          enabled: false,
          feature: %Environment.Feature{
            id: 18382,
            name: "test_identity",
            type: "STANDARD"
          },
          feature_state_value: "very_yes",
          featurestate_uuid: "a2c61335-2249-4c1f-818d-fc0b6cf7552a",
          multivariate_feature_state_values: []
        }
      ],
      project: %Environment.Project{
        id: 4732,
        name: "testing-api",
        hide_disabled_flags: false,
        organisation: %Environment.Organisation{
          id: 4131,
          name: "Mr. Bojangles Inc",
          feature_analytics: false,
          persist_trait_data: true,
          stop_serving_flags: false
        },
        segments: [
          %Segments.Segment{
            feature_states: [],
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
                        property: nil,
                        value: "false"
                      }
                    ],
                    rules: [],
                    type: "ANY"
                  }
                ],
                type: "ALL"
              }
            ]
          },
          %Segments.Segment{
            feature_states: [],
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
                        property: nil,
                        value: "30"
                      }
                    ],
                    rules: [],
                    type: "ANY"
                  }
                ],
                type: "ALL"
              }
            ]
          }
        ]
      }
    }
  end

  def identities_list() do
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
          trait_value: "false"
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
      "id" => FlagsmithEngine.Test.IDKeeper.get_and_update(),
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
      "id" => FlagsmithEngine.Test.IDKeeper.get_and_update()
    }
  end
end
