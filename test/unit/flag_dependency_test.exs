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
      },
      %{
        "django_id" => 4,
        "enabled" => true,
        "feature" => %{"id" => 3, "name" => "banner", "type" => "STANDARD"},
        "feature_state_value" => "hello"
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
        },
        %{
          "id" => 2,
          "name" => "without_plan",
          "rules" => [
            %{
              "type" => "ALL",
              "rules" => [],
              "conditions" => [%{"operator" => "IS_NOT_SET", "property_" => "plan"}]
            }
          ],
          "feature_states" => [
            %{
              "django_id" => 5,
              "enabled" => true,
              "feature" => %{"id" => 3, "name" => "banner", "type" => "STANDARD"},
              "feature_state_value" => "hello stranger",
              "feature_segment" => %{"priority" => 1}
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

    assert [
             %Segments.IdentitySegment{id: 1, name: "prerequisite_enabled"},
             %Segments.IdentitySegment{id: 2, name: "without_plan"}
           ] = segments
  end

  test "dependent flag keeps its default when its prerequisite is disabled", %{env: env} do
    # Given
    identity = Identity.from_id_traits("other-user", [])

    # When
    dependent = Engine.get_identity_feature_state(env, identity, "dependent")
    segments = Engine.get_identity_segments(env, identity)

    # Then
    assert %{enabled: false, feature_state_value: "off"} = dependent
    assert [%Segments.IdentitySegment{id: 2, name: "without_plan"}] = segments
  end

  test "environment flags keep a dependent flag's default while its prerequisite is disabled", %{
    env: env
  } do
    # Given / When
    feature_states = Engine.get_environment_feature_states(env)

    # Then
    assert [
             %{feature: %{name: "prerequisite"}, enabled: false},
             %{feature: %{name: "dependent"}, enabled: false, feature_state_value: "off"},
             %{feature: %{name: "banner"}}
           ] = feature_states
  end

  test "environment flags follow a prerequisite enabled for the environment", %{env: env} do
    # Given
    env = enable_prerequisite(env)

    # When
    feature_states = Engine.get_environment_feature_states(env)

    # Then
    assert [
             %{feature: %{name: "prerequisite"}, enabled: true},
             %{feature: %{name: "dependent"}, enabled: true, feature_state_value: "on"},
             %{feature: %{name: "banner"}}
           ] = feature_states
  end

  test "environment flags ignore segments that need an identity", %{env: env} do
    # Given / When
    banner = Engine.get_environment_feature_state(env, "banner")

    # Then
    assert %{enabled: true, feature_state_value: "hello"} = banner
  end

  test "environment flags hidden when disabled include a flag its prerequisite enables", %{
    env: env
  } do
    # Given
    env = enable_prerequisite(env)
    env = %{env | project: %{env.project | hide_disabled_flags: true}}

    # When
    feature_states = Engine.get_environment_feature_states(env)

    # Then
    assert [
             %{feature: %{name: "prerequisite"}},
             %{feature: %{name: "dependent"}, feature_state_value: "on"},
             %{feature: %{name: "banner"}}
           ] = feature_states
  end

  test "environment flags hidden when disabled leave out a flag its prerequisite disables", %{
    env: env
  } do
    # Given
    env = %{env | project: %{env.project | hide_disabled_flags: true}}

    # When
    feature_states = Engine.get_environment_feature_states(env)

    # Then
    assert [%{feature: %{name: "banner"}}] = feature_states
  end

  defp enable_prerequisite(%{feature_states: [prerequisite | feature_states]} = env),
    do: %{env | feature_states: [%{prerequisite | enabled: true} | feature_states]}
end
