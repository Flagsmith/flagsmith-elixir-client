defmodule Flagsmith.Engine.Mappers do
  @moduledoc false

  alias Flagsmith.Schemas.{Environment, Features, Identity, Segments, Traits}

  @identity_overrides_segment_key "identity_overrides"

  @doc """
  Map an environment, an identity, and optionally traits overriding those of
  the identity, to an evaluation context for `Flagsmith.Engine.Evaluator`.

  Feature and segment contexts carry the feature state or segment they were
  mapped from in their metadata, so that results can be mapped back to them.
  """
  @spec map_environment_identity_to_context(
          Environment.t(),
          Identity.t(),
          list(Traits.Trait.t())
        ) :: Flagsmith.Engine.Evaluator.context()
  def map_environment_identity_to_context(
        %Environment{
          api_key: api_key,
          feature_states: feature_states,
          project: %Environment.Project{segments: segments}
        } = environment,
        %Identity{identifier: identifier, identity_features: identity_features} = identity,
        override_traits \\ []
      ) do
    identity = Identity.set_env_key(identity, environment)

    traits =
      case override_traits do
        [_ | _] -> override_traits
        _ -> identity.traits
      end

    %{
      "environment" => %{"key" => api_key, "name" => environment.name},
      "identity" => %{
        "identifier" => identifier,
        "key" => to_string(Identity.composite_key(identity)),
        "traits" => Map.new(traits, &map_trait/1)
      },
      "features" => Enum.map(feature_states, &{&1.feature.name, map_feature_state(&1)}),
      "segments" =>
        Enum.map(segments, &{to_string(&1.id), map_segment(&1)}) ++
          map_identity_overrides(identifier, identity_features)
    }
  end

  defp map_trait(%Traits.Trait{trait_key: key, trait_value: %Traits.Trait.Value{value: value}}),
    do: {key, map_trait_value(value)}

  defp map_trait(%Traits.Trait{trait_key: key, trait_value: value}),
    do: {key, map_trait_value(value)}

  defp map_trait_value(%Version{} = value), do: Version.to_string(value)
  defp map_trait_value(value), do: value

  defp map_segment(%Segments.Segment{id: id, name: name} = segment) do
    %{
      "key" => to_string(id),
      "name" => name,
      "rules" => Enum.map(segment.rules, &map_rule/1),
      "overrides" => Enum.map(segment.feature_states, &map_feature_state/1),
      "metadata" => %{segment: segment}
    }
  end

  defp map_rule(%Segments.Segment.Rule{type: type, rules: rules, conditions: conditions}) do
    %{
      "type" => to_string(type),
      "rules" => Enum.map(rules, &map_rule/1),
      "conditions" =>
        Enum.map(conditions, fn %Segments.Segment.Condition{} = condition ->
          %{
            "property" => condition.property_ || "",
            "operator" => to_string(condition.operator),
            "value" => condition.value
          }
        end)
    }
  end

  defp map_feature_state(%Environment.FeatureState{} = feature_state) do
    feature_context = %{
      "key" => Environment.FeatureState.get_hashing_id(feature_state),
      "name" => feature_state.feature.name,
      "enabled" => feature_state.enabled,
      "value" => feature_state.feature_state_value,
      "metadata" => %{feature_state: feature_state}
    }

    feature_context =
      case feature_state.multivariate_feature_state_values do
        [_ | _] = values -> Map.put(feature_context, "variants", Enum.map(values, &map_variant/1))
        _ -> feature_context
      end

    case feature_state.feature_segment do
      %Environment.FeatureState.FeatureSegment{priority: priority} ->
        Map.put(feature_context, "priority", priority)

      nil ->
        feature_context
    end
  end

  defp map_variant(%Environment.MultivariateFeatureStateValue{} = value) do
    %{
      "value" => value.multivariate_feature_option.value,
      "weight" => value.percentage_allocation,
      "priority" => value.id || value.mv_fs_value_uuid
    }
  end

  # a segment matching the identity alone, taking precedence over any other
  defp map_identity_overrides(_identifier, []), do: []

  defp map_identity_overrides(identifier, identity_features) do
    [
      {@identity_overrides_segment_key,
       %{
         "key" => @identity_overrides_segment_key,
         "name" => @identity_overrides_segment_key,
         "rules" => [
           %{
             "type" => "ALL",
             "conditions" => [
               %{
                 "property" => "$.identity.identifier",
                 "operator" => "IN",
                 "value" => [identifier]
               }
             ]
           }
         ],
         "overrides" =>
           Enum.map(identity_features, fn %Features.FeatureState{} = feature_state ->
             %{
               "key" => "",
               "name" => feature_state.feature.name,
               "enabled" => feature_state.enabled,
               "value" => feature_state.feature_state_value,
               "priority" => :negative_infinity,
               "metadata" => %{feature_state: feature_state}
             }
           end)
       }}
    ]
  end
end
