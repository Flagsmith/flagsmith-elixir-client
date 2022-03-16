defmodule Flagsmith.Engine do
  alias Flagsmith.Schemas.{
    Environment,
    Traits,
    Segments,
    Identity,
    Features
  }

  alias Traits.Trait
  alias Flagsmith.Schemas.Types
  @condition_operators Flagsmith.Schemas.Types.Operator.values(:atoms)

  @moduledoc false

  @doc """
  Generate a valid environment struct from a json string or map.
  """
  @spec parse_environment(data :: map() | String.t()) ::
          {:ok, Environment.t()} | {:error, Ecto.Changeset.t()} | {:error, term()}
  def parse_environment(data) when is_map(data) and not is_struct(data),
    do: Environment.cast(data)

  def parse_environment(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> parse_environment(decoded)
      {:error, _} = error -> error
    end
  end

  @doc """
  Get the feature states of an `t:Flagsmith.Schemas.Environment.t/0`.
  """
  @spec get_environment_feature_states(Environment.t()) :: list(Environment.FeatureState.t())
  def get_environment_feature_states(%Environment{
        feature_states: feature_states,
        project: %Environment.Project{hide_disabled_flags: hide_disabled_flags}
      }) do
    case hide_disabled_flags do
      false -> feature_states
      true -> Enum.filter(feature_states, & &1.enabled)
    end
  end

  @doc """
  Get a specific feature state for a given feature_name in a given 
  `t:Flagsmith.Schemas.Environment.t/0`.
  """
  @spec get_environment_feature_state(Environment.t(), name :: String.t()) ::
          Environment.FeatureState.t() | nil
  def get_environment_feature_state(%Environment{feature_states: fs}, name),
    do: Enum.find(fs, fn %{feature: %{name: f_name}} -> f_name == name end)

  @doc """
  Get list of feature states for a given `t:Flagsmith.Schemas.Identity.t/0` in a 
  given `t:Flagsmith.Schemas.Environment.t/0`.
  """
  @spec get_identity_feature_states(
          Environment.t(),
          Identity.t(),
          override_traits :: list(Traits.Trait.t())
        ) :: list(Environment.FeatureState.t())
  def get_identity_feature_states(
        %Environment{
          feature_states: fs,
          project: %Environment.Project{segments: segments}
        } = env,
        %Identity{flags: identity_features} = identity,
        override_traits \\ []
      ) do
    with identity <- Identity.set_env_key(identity, env),
         segment_features <- get_segment_features(segments, identity, override_traits),
         replaced <- replace_segment_features(fs, segment_features),
         pre_features <- replace_identity_features(replaced, identity_features),
         final_features <- replace_multivariates(pre_features, identity) do
      final_features
    end
  end

  defp replace_multivariates(features, %Identity{identifier: identity_id}) do
    features
    |> Enum.map(fn %{feature: %{type: type}} = feature_state ->
      case type do
        "MULTIVARIATE" ->
          uuid = Environment.FeatureState.get_hashing_id(feature_state)
          mv_fs = Map.get(feature_state, :multivariate_feature_state_values, [])
          percentage = percentage_from_ids([uuid, identity_id])

          case find_first_multivariate(mv_fs, percentage) do
            {:ok, new_value} -> %{feature_state | feature_state_value: new_value}
            _ -> feature_state
          end

        _ ->
          feature_state
      end
    end)
  end

  defp find_first_multivariate(mvs, percentage) do
    Enum.reduce_while(mvs, 0, fn %{percentage_allocation: p_allot} = mv, start_perc ->
      limit = p_allot + start_perc

      case start_perc <= percentage and percentage < limit do
        true -> {:halt, Environment.FeatureState.extract_multivariate_value(mv)}
        _ -> {:cont, limit}
      end
    end)
  end

  @doc """
  Get feature state with a given feature_name for a given `t:Flagsmith.Schemas.Identity.t/0`
  and `t:Flagsmith.Schemas.Environment.t/0`.
  """
  @spec get_identity_feature_state(
          Environment.t(),
          Identity.t(),
          name :: String.t(),
          override_traits :: list(Traits.Trait.t())
        ) :: Environment.FeatureState.t() | nil
  def get_identity_feature_state(
        %Environment{} = env,
        %Identity{} = identity,
        name,
        override_traits \\ []
      ) do
    env
    |> get_identity_feature_states(identity, override_traits)
    |> Enum.find(fn %{feature: %{name: f_name}} -> f_name == name end)
  end

  @doc """
  Filters a list of segments accordingly to if they match an identity and traits
  (optionally using a list of traits to override those in the identity)
  """
  @spec get_segment_features(
          segments :: list(Segments.Segment.t()),
          Identity.t(),
          override_traits :: list(Traits.Trait.t())
        ) :: list(Segments.Segment.t())
  def get_segment_features(segments, identity, override_traits) do
    Enum.filter(segments, fn segment ->
      evaluate_identity_in_segment(identity, segment, override_traits)
    end)
  end

  @doc """
  Returns a list of `t:Flagsmith.Schemas.Environment.FeatureState.t/0` where any that
  has the same name as in the segments provided is replaced by the feature state there
  specified (if any).
  """
  @spec replace_segment_features(
          original :: list(Environment.FeatureState.t()),
          to_replace :: list(Segments.Segment.t())
        ) :: list(Environment.FeatureState.t())
  def replace_segment_features(original, to_replace) do
    Enum.reduce(to_replace, original, fn %{feature_states: segment_fs}, acc ->
      inverted = Enum.reverse(segment_fs)

      Enum.map(acc, fn %{feature: %{name: feature_name}} = flag ->
        Enum.find(inverted, flag, fn %{feature: %{name: replacement_name}} ->
          replacement_name == feature_name
        end)
      end)
    end)
  end

  @doc """
  Returns a list with elements of any of `t:Flagsmith.Schemas.Environment.FeatureState.t/0`
  or `t:Flagsmith.Schemas.Features.FeatureState.t/0` where any that has the same name
  as in any of the identity `t:Flagsmith.Schemas.Features.FeatureState.t/0` provided
  is replaced by that feature.
  """
  @spec replace_identity_features(
          original :: list(Environment.FeatureState.t()),
          to_replace :: list(Features.FeatureState.t())
        ) :: list(Environment.FeatureState.t() | Features.FeatureState.t())
  def replace_identity_features(original, to_replace) do
    Enum.reduce(to_replace, original, fn %{feature: %{name: replacement_name}} = replacement_flag,
                                         acc ->
      Enum.map(acc, fn %{feature: %{name: feature_name}} = flag ->
        case feature_name == replacement_name do
          true -> replacement_flag
          false -> flag
        end
      end)
    end)
  end

  @doc """
  True if an identity is deemed matching a segment conditions & rules, false otherwise.
  """
  @spec evaluate_identity_in_segment(Identity.t(), Segments.Segment.t(), list(Traits.Trait.t())) ::
          boolean()

  # if there's no rules we say it doesn't match but I'm not sure this is how it
  # should be
  def evaluate_identity_in_segment(_, %Segments.Segment{rules: []}, _),
    do: false

  def evaluate_identity_in_segment(
        %Identity{traits: identity_traits} = identity,
        %Segments.Segment{id: segment_id, rules: rules},
        override_traits
      ) do
    traits =
      case override_traits do
        [_ | _] -> override_traits
        _ -> identity_traits
      end

    Enum.all?(rules, fn rule ->
      traits_match_segment_rule(traits, rule, segment_id, Identity.composite_key(identity))
    end)
  end

  @doc """
  True if the segment rule conditions all match (or there's no conditions) and all
  nested rules too (or there's no rules), false otherwise.

  """
  @spec traits_match_segment_rule(
          list(Traits.Trait.t()),
          Segments.Segment.Rule.t(),
          non_neg_integer(),
          String.t()
        ) :: boolean()
  def traits_match_segment_rule(
        traits,
        %Segments.Segment.Rule{type: type, rules: rules, conditions: conditions},
        segment_id,
        identifier
      ) do
    matching_function = Types.Segment.Type.enum_matching_function(type)

    (length(conditions) == 0 or
       matching_function.(conditions, fn condition ->
         traits_match_segment_condition(
           traits,
           condition,
           segment_id,
           identifier
         )
       end)) and
      (length(rules) == 0 or
         matching_function.(rules, fn rule ->
           traits_match_segment_rule(traits, rule, segment_id, identifier)
         end))
  end

  @doc """
  True if according to the type of condition operator the co mparison is true, false
  otherwise. With exception for PERCENTAGE_SPLIT operator all others are matched against
  the traits passed in.
  """
  @spec traits_match_segment_condition(
          list(Traits.Trait.t()),
          Segments.Segment.Condition.t(),
          non_neg_integer(),
          String.t()
        ) :: boolean()
  def traits_match_segment_condition(
        _traits,
        %Segments.Segment.Condition{operator: :PERCENTAGE_SPLIT, value: value},
        segment_id,
        identifier
      ) do
    with {_, {float, _}} <- {:float_parse, Float.parse(value)},
         {_, percentage} <-
           {:percentage, percentage_from_ids([segment_id, identifier], 1)} do
      percentage <= float
    else
      {_what, _} ->
        false
    end
  end

  def traits_match_segment_condition(
        traits,
        %Segments.Segment.Condition{operator: operator, value: value, property_: prop},
        _segment_id,
        _identifier
      ) do
    Enum.any?(traits, fn %Traits.Trait{
                           trait_key: t_key,
                           trait_value: t_value
                         } ->
      case prop == t_key do
        true ->
          case cast_value(t_value, value) do
            {:ok, casted} ->
              trait_match(operator, casted, t_value)

            _ ->
              false
          end

        _ ->
          false
      end
    end)
  end

  @doc """
  Given a list of ids in either and optionally a number of to duplicate them n times,
  compute a value representing a percentage to which those ids when hashed match.
  Refer to https://github.com/Flagsmith/flagsmith-engine/blob/c34b4baeea06d31d221433053b64c1e855fd8d4d/flag_engine/utils/hashing.py#L5
  """
  @spec percentage_from_ids(list(String.t() | non_neg_integer()), non_neg_integer()) :: float()
  def percentage_from_ids(original_ids, iterations \\ 1) do
    with {_, as_strings} <- {:strings, Enum.map(original_ids, &id_to_string/1)},
         {_, ids} <- {:ids, List.duplicate(as_strings, iterations)},
         {_, stringed} <- {:join, List.flatten(ids) |> Enum.join(",")},
         {_, hashed} <- {:hash, Flagsmith.Engine.HashingBehaviour.hash(stringed)},
         {_, {int, _}} <- {:int_parse, Integer.parse(hashed, 16)} do
      case Integer.mod(int, 9999) / 9998 * 100 do
        100.0 ->
          percentage_from_ids(original_ids, iterations + 1)

        percentage ->
          percentage
      end
    else
      {_, _} = error -> {:error, error}
    end
  end

  defp id_to_string(ids) when is_list(ids), do: Enum.map(ids, &id_to_string/1)
  defp id_to_string(int) when is_integer(int), do: Integer.to_string(int)
  defp id_to_string(bin) when is_binary(bin), do: bin
  defp id_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)

  @doc """
  Given an `t:Flagsmith.Schemas.Types.Operator.t/0`, a cast or uncast segment value, and a cast trait 
  value, evaluate if the trait value matches to the segment value.
  """
  @spec trait_match(
          condition :: Types.Operator.t(),
          segment_value :: String.t() | Trait.Value.t(),
          trait :: Trait.Value.t()
        ) :: boolean()
  def trait_match(:NOT_CONTAINS, %Trait.Value{type: :string, value: value}, %Trait.Value{
        type: :string,
        value: t_value
      }),
      do: not String.contains?(t_value, value)

  def trait_match(:CONTAINS, %Trait.Value{value: value}, %Trait.Value{value: t_value}),
    do: String.contains?(t_value, value)

  def trait_match(:REGEX, %Trait.Value{type: :string, value: value}, %Trait.Value{
        type: :string,
        value: t_value
      }) do
    case Regex.compile(value) do
      {:ok, regex} ->
        String.match?(t_value, regex)

      _ ->
        false
    end
  end

  def trait_match(:GREATER_THAN, %Trait.Value{value: value}, %Trait.Value{
        type: type,
        value: t_value
      }) do
    case type do
      :decimal -> Decimal.compare(t_value, value) == :gt
      _ -> t_value > value
    end
  end

  def trait_match(
        :GREATER_THAN_INCLUSIVE,
        %Trait.Value{value: value},
        %Trait.Value{type: type, value: t_value}
      ) do
    case type do
      :decimal -> Decimal.compare(t_value, value) in [:gt, :eq]
      _ -> t_value >= value
    end
  end

  def trait_match(:LESS_THAN, %Trait.Value{value: value}, %Trait.Value{type: type, value: t_value}) do
    case type do
      :decimal -> Decimal.compare(t_value, value) == :lt
      _ -> t_value < value
    end
  end

  def trait_match(:LESS_THAN_INCLUSIVE, %Trait.Value{value: value}, %Trait.Value{
        type: type,
        value: t_value
      }) do
    case type do
      :decimal -> Decimal.compare(t_value, value) in [:lt, :eq]
      _ -> t_value <= value
    end
  end

  def trait_match(:EQUAL, %Trait.Value{value: value}, %Trait.Value{type: type, value: t_value}) do
    case type do
      :decimal -> Decimal.equal?(t_value, value)
      _ -> t_value == value
    end
  end

  def trait_match(:NOT_EQUAL, %Trait.Value{value: value}, %Trait.Value{type: type, value: t_value}) do
    case type do
      :decimal -> not Decimal.equal?(t_value, value)
      _ -> t_value != value
    end
  end

  def trait_match(condition, not_cast, %Trait.Value{} = t_value_struct)
      when condition in @condition_operators and not is_struct(not_cast) and not is_map(not_cast) do
    case cast_value(t_value_struct, not_cast) do
      {:ok, cast} ->
        trait_match(condition, cast, t_value_struct)

      _ ->
        false
    end
  end

  def trait_match(_, _, _), do: false

  defp cast_value(%Trait.Value{} = trait_value, to_convert) do
    with {:ok, converted} <- Trait.Value.convert_value_to(trait_value, to_convert) do
      Trait.Value.cast(converted)
    end
  end
end
