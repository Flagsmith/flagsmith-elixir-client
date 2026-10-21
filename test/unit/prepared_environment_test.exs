defmodule Flagsmith.Engine.PreparedEnvironment.Test do
  use ExUnit.Case, async: true

  import Mox, only: [stub_with: 2]

  alias Flagsmith.Engine
  alias Flagsmith.Schemas.Identity

  @environment %{
    "api_key" => "env-key",
    "feature_states" => [
      %{
        "django_id" => 1,
        "enabled" => false,
        "feature" => %{"id" => 1, "name" => "feature", "type" => "STANDARD"},
        "feature_state_value" => "environment"
      }
    ],
    "project" => %{
      "hide_disabled_flags" => false,
      "segments" => [
        %{
          "id" => 1,
          "name" => "segment",
          "rules" => [
            %{
              "type" => "ALL",
              "rules" => [],
              "conditions" => [
                %{"operator" => "EQUAL", "property_" => "plan", "value" => "premium"}
              ]
            }
          ],
          "feature_states" => [
            %{
              "django_id" => 2,
              "enabled" => true,
              "feature" => %{"id" => 1, "name" => "feature", "type" => "STANDARD"},
              "feature_state_value" => "segment",
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

    identity =
      Identity.from_id_traits("user", [%{"trait_key" => "plan", "trait_value" => "premium"}])

    [env: env, identity: identity]
  end

  test "an environment changed after an evaluation is evaluated as changed", %{
    env: env,
    identity: identity
  } do
    # Given
    %{project: %{segments: [segment]} = project} = env

    changed_rule =
      put_in(hd(segment.rules).conditions, [%{hd(hd(segment.rules).conditions) | value: "free"}])

    changed_env = %{env | project: %{project | segments: [%{segment | rules: [changed_rule]}]}}

    # When
    before = Engine.get_identity_feature_state(env, identity, "feature")
    changed = Engine.get_identity_feature_state(changed_env, identity, "feature")
    unchanged = Engine.get_identity_feature_state(env, identity, "feature")

    # Then
    assert %{enabled: true, feature_state_value: "segment"} = before
    assert %{enabled: false, feature_state_value: "environment"} = changed
    assert unchanged == before
  end
end
