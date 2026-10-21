defmodule Flagsmith.Engine.FlagDependency.Test do
  use ExUnit.Case, async: true

  import Mox, only: [stub_with: 2]

  alias Flagsmith.Engine
  alias Flagsmith.Schemas.{Identity, Segments}

  @environment %{
    "api_key" => "env-key",
    "name" => "Environment",
    "feature_states" => [
      %{
        "django_id" => 1,
        "enabled" => false,
        "feature" => %{"id" => 1, "name" => "prerequisite", "type" => "STANDARD"},
        "feature_state_value" => nil
      },
      %{
        "django_id" => 2,
        "enabled" => false,
        "feature" => %{"id" => 2, "name" => "dependent", "type" => "STANDARD"},
        "feature_state_value" => "off"
      }
    ],
    "identity_overrides" => [
      %{
        "identifier" => "prerequisite-user",
        "identity_features" => [
          %{
            "enabled" => true,
            "feature" => %{"id" => 1, "name" => "prerequisite", "type" => "STANDARD"},
            "feature_state_value" => nil
          }
        ]
      }
    ],
    "project" => %{
      "hide_disabled_flags" => false,
      "segments" => [
        %{
          "id" => 1,
          "name" => "prerequisite_enabled",
          "rules" => [
            %{
              "type" => "ALL",
              "rules" => [],
              "conditions" => [
                %{
                  "operator" => "EQUAL",
                  "property_" => "$.flags.prerequisite.enabled",
                  "value" => "true"
                }
              ]
            }
          ],
          "feature_states" => [
            %{
              "django_id" => 3,
              "enabled" => true,
              "feature" => %{"id" => 2, "name" => "dependent", "type" => "STANDARD"},
              "feature_state_value" => "on",
              "feature_segment" => %{"priority" => 0}
            }
          ]
        }
      ]
    }
  }

  setup do
    stub_with(Flagsmith.Engine.MockHashing, Flagsmith.Engine.HashingUtils)
    {:ok, env} = Engine.parse_environment(@environment)
    overrides = Map.new(env.identity_overrides, &{&1.identifier, &1})
    [env: env, overrides: overrides]
  end

  test "dependent flag follows its prerequisite's identity override", %{
    env: env,
    overrides: overrides
  } do
    # Given
    identity = Map.fetch!(overrides, "prerequisite-user")

    # When
    dependent = Engine.get_identity_feature_state(env, identity, "dependent")
    segments = Engine.get_identity_segments(env, identity)

    # Then
    assert %{enabled: true, feature_state_value: "on"} = dependent
    assert [%Segments.IdentitySegment{id: 1, name: "prerequisite_enabled"}] = segments
  end

  test "dependent flag keeps its default when its prerequisite is disabled", %{env: env} do
    # Given
    identity = Identity.from_id_traits("other-user", [])

    # When
    dependent = Engine.get_identity_feature_state(env, identity, "dependent")
    segments = Engine.get_identity_segments(env, identity)

    # Then
    assert %{enabled: false, feature_state_value: "off"} = dependent
    assert [] = segments
  end
end
