defmodule Flagsmith.Engine.Evaluator do
  @moduledoc false

  alias Flagsmith.Engine.JSONPath

  @type context :: map()
  @type prepared :: map()
  @type flag_result :: %{String.t() => term()}
  @type result :: %{String.t() => term()}

  @circular_dependency_reason "ERROR; code=CIRCULAR_DEPENDENCY"

  @comparison_operators [
    "EQUAL",
    "NOT_EQUAL",
    "GREATER_THAN",
    "GREATER_THAN_INCLUSIVE",
    "LESS_THAN",
    "LESS_THAN_INCLUSIVE",
    "CONTAINS"
  ]

  @doc """
  Get the flags and matching segments for an evaluation context, as specified by
  https://github.com/Flagsmith/engine-test-data.

  Contexts and results are maps with string keys, matching their JSON form.
  `features` and `segments` may also be given as lists of `{key, value}` tuples,
  to keep the order that decides override ties and the order of segment results.

  Segment conditions may read other flags, e.g. `$.flags.<name>.enabled`. A flag
  read this way is resolved with its own segment overrides, and features in a
  dependency cycle are reported as `ERROR; code=CIRCULAR_DEPENDENCY`.
  """
  @spec get_evaluation_result(context()) :: result()
  def get_evaluation_result(context) do
    context
    |> prepare()
    |> evaluate(Map.get(context, "identity"))
  end

  @doc """
  Prepare everything but the identity of a context for evaluation, so that the
  work it takes is shared by every identity evaluated with `evaluate/3`.
  """
  @spec prepare(context()) :: prepared()
  def prepare(context) do
    features = entries(Map.get(context, "features"))
    segments = Enum.map(entries(Map.get(context, "segments")), &prepare_segment/1)

    %{
      context:
        context
        |> Map.delete("identity")
        |> Map.merge(%{
          "features" => Map.new(features),
          "segments" => Map.new(segments, fn {key, segment} -> {key, segment.context} end)
        }),
      environment_key: get_in(context, ["environment", "key"]),
      features: features,
      features_by_key: Map.new(features),
      segments: segments,
      segments_by_key: Map.new(segments),
      segment_keys_by_feature_name: segment_keys_by_feature_name(segments)
    }
  end

  @doc """
  Evaluate a prepared context for an identity, or none.

  Options:

    * `:segments` - segments to evaluate after those of the prepared context,
      as `{key, segment}` tuples
    * `:flags` - whether to evaluate flags, or only segments. Defaults to `true`
  """
  @spec evaluate(prepared(), map() | nil, keyword()) :: result()
  def evaluate(prepared, identity, opts \\ []) do
    evaluation = add_segments(prepared, Keyword.get(opts, :segments, []))
    identity = enrich_identity(identity, prepared.environment_key)

    evaluation =
      Map.merge(evaluation, %{
        context: put_identity(evaluation.context, identity),
        identity_key: identity && Map.get(identity, "key"),
        traits: (identity && Map.get(identity, "traits")) || %{}
      })

    state = %{
      resolved: %{},
      cyclic: MapSet.new(),
      used: false,
      cycle_hits: 0,
      # most recent first
      resolving: [],
      segment_matches: %{}
    }

    {segment_results, segment_overrides, state} = evaluate_segments(evaluation, state)

    flags =
      case Keyword.get(opts, :flags, true) do
        true -> evaluate_features(evaluation, segment_overrides, state)
        false -> %{}
      end

    %{"flags" => flags, "segments" => segment_results}
  end

  defp entries(nil), do: []
  defp entries(map) when is_map(map), do: Enum.to_list(map)
  defp entries(list) when is_list(list), do: list

  defp add_segments(evaluation, []), do: evaluation

  defp add_segments(evaluation, segments) do
    segments = Enum.map(segments, &prepare_segment/1)

    keys_by_feature_name =
      Map.merge(
        evaluation.segment_keys_by_feature_name,
        segment_keys_by_feature_name(segments),
        fn _name, keys, added_keys -> keys ++ added_keys end
      )

    %{
      evaluation
      | context:
          Map.update!(evaluation.context, "segments", fn context_segments ->
            Enum.reduce(segments, context_segments, fn {key, segment}, context_segments ->
              Map.put(context_segments, key, segment.context)
            end)
          end),
        segments: evaluation.segments ++ segments,
        segments_by_key: Map.merge(evaluation.segments_by_key, Map.new(segments)),
        segment_keys_by_feature_name: keys_by_feature_name
    }
  end

  defp enrich_identity(%{"identifier" => identifier} = identity, environment_key) do
    case Map.get(identity, "key") do
      key when key in [nil, ""] -> Map.put(identity, "key", "#{environment_key}_#{identifier}")
      _ -> identity
    end
  end

  defp enrich_identity(identity, _environment_key), do: identity

  defp put_identity(context, nil), do: context
  defp put_identity(context, identity), do: Map.put(context, "identity", identity)

  defp segment_keys_by_feature_name(segments) do
    segments
    |> Enum.flat_map(fn {segment_key, segment} ->
      Enum.map(segment.overrides, &{&1.name, segment_key})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp prepare_segment({key, segment}) do
    segment_key = Map.get(segment, "key")

    rules =
      case Map.get(segment, "rules") do
        [_ | _] = rules -> Enum.map(rules, &prepare_rule(&1, segment_key))
        _ -> nil
      end

    overrides =
      for override <- Map.get(segment, "overrides") || [] do
        %{name: Map.get(override, "name"), priority: priority(override), feature: override}
      end

    {key,
     %{
       context: segment,
       name: Map.get(segment, "name"),
       rules: rules,
       overrides: overrides,
       result: segment_result(segment)
     }}
  end

  defp prepare_rule(rule, segment_key) do
    conditions =
      case Map.get(rule, "conditions") do
        [_ | _] = conditions -> Enum.map(conditions, &prepare_condition(&1, segment_key))
        _ -> []
      end

    rules =
      case Map.get(rule, "rules") do
        [_ | _] = rules -> Enum.map(rules, &prepare_rule(&1, segment_key))
        _ -> []
      end

    case Map.get(rule, "type") do
      type when type in ["ALL", "ANY", "NONE"] -> {type, conditions, rules}
      _ -> :invalid
    end
  end

  defp prepare_condition(condition, segment_key) do
    operator = Map.get(condition, "operator")
    property = Map.get(condition, "property")

    property =
      case operator == "PERCENTAGE_SPLIT" and property in [nil, ""] do
        # legacy segments split on the identity key
        true -> :identity_key
        false -> prepare_property(property || "")
      end

    {operator, property, prepare_value(operator, Map.get(condition, "value"), segment_key)}
  end

  defp prepare_property("$." <> _ = property) do
    case JSONPath.compile(property) do
      {:ok, segments} -> {:path, property, segments}
      :error -> {:trait, property}
    end
  end

  defp prepare_property(property), do: {:trait, property}

  defp prepare_value("IN", value, _segment_key), do: in_values(value)

  defp prepare_value("PERCENTAGE_SPLIT", value, segment_key),
    do: {parse_float(value), to_str(segment_key)}

  defp prepare_value("NOT_CONTAINS", value, _segment_key), do: to_str(value)

  defp prepare_value("REGEX", value, _segment_key) do
    case :re.compile(to_str(value), [:unicode, :ucp]) do
      {:ok, regex} -> {:ok, regex}
      {:error, _} -> :error
    end
  end

  defp prepare_value("MODULO", value, _segment_key) when is_binary(value) do
    with [divisor, remainder] <- String.split(value, "|"),
         {:ok, divisor} when divisor != 0 <- parse_float(divisor),
         {:ok, remainder} <- parse_float(remainder) do
      {:ok, divisor, remainder}
    else
      _ -> :error
    end
  end

  defp prepare_value("MODULO", _value, _segment_key), do: :error

  defp prepare_value(operator, value, _segment_key) when operator in @comparison_operators do
    version =
      case semver?(value) do
        true -> Version.parse(String.replace_suffix(value, ":semver", ""))
        false -> nil
      end

    %{version: version, value: value, string: to_str(value)}
  end

  defp prepare_value(_operator, value, _segment_key), do: value

  defp evaluate_segments(evaluation, state) do
    {results, overrides, state, _cycle_hits} =
      Enum.reduce(evaluation.segments, {[], %{}, state, state.cycle_hits}, fn {_key, segment},
                                                                              {results, overrides,
                                                                               state,
                                                                               cycle_hits} ->
        {matches, state} = context_in_segment?(evaluation, state, segment)

        cond do
          state.cycle_hits != cycle_hits ->
            # a verdict resting on an unresolvable flag is unsound either way
            {results, overrides, state, state.cycle_hits}

          not matches ->
            {results, overrides, state, cycle_hits}

          true ->
            overrides =
              Enum.reduce(segment.overrides, overrides, fn %{name: name} = override, overrides ->
                case wins_over?(override, overrides) do
                  true -> Map.put(overrides, name, {override, segment.name})
                  false -> overrides
                end
              end)

            {[segment.result | results], overrides, state, cycle_hits}
        end
      end)

    {Enum.reverse(results), overrides, state}
  end

  defp segment_result(%{"name" => name} = segment) do
    case Map.get(segment, "metadata") do
      metadata when metadata in [nil, %{}] -> %{"name" => name}
      metadata -> %{"name" => name, "metadata" => metadata}
    end
  end

  # lower priority wins, the first seen wins a tie
  defp wins_over?(%{name: name, priority: priority}, overrides) do
    case overrides do
      %{^name => {incumbent, _segment_name}} -> priority < incumbent.priority
      _ -> true
    end
  end

  defp priority(%{"priority" => :negative_infinity}), do: {0, 0}
  defp priority(%{"priority" => priority}) when is_number(priority), do: {1, priority}
  defp priority(_), do: {2, 0}

  defp evaluate_features(evaluation, segment_overrides, state) do
    flags =
      Map.new(evaluation.features, fn {_key, %{"name" => name} = feature} ->
        flag =
          case segment_overrides do
            %{^name => {override, segment_name}} ->
              flag_result(
                evaluation,
                override.feature,
                "TARGETING_MATCH; segment=#{segment_name}"
              )

            _ ->
              flag_result(evaluation, feature, fallback_reason(evaluation, name))
          end

        {name, flag}
      end)

    case state.used do
      false ->
        flags

      true ->
        # flags resolved for conditions are cycle-guarded, so take precedence
        Enum.reduce(state.cyclic, Map.merge(flags, state.resolved), fn feature_name, flags ->
          case flags do
            %{^feature_name => flag} ->
              Map.put(flags, feature_name, %{flag | "reason" => @circular_dependency_reason})

            _ ->
              flags
          end
        end)
    end
  end

  defp fallback_reason(%{segment_keys_by_feature_name: keys}, name)
       when is_map_key(keys, name),
       do: "DEFAULT"

  defp fallback_reason(_, _), do: "STATIC"

  defp flag_result(evaluation, feature, reason) do
    {value, variant, reason} =
      case {evaluation.identity_key, Map.get(feature, "variants")} do
        {key, [_ | _] = variants} when not is_nil(key) ->
          select_variant(feature, key, variants, reason)

        _ ->
          {Map.get(feature, "value"), nil, reason}
      end

    result = %{
      "enabled" => Map.get(feature, "enabled"),
      "name" => Map.get(feature, "name"),
      "reason" => reason,
      "value" => value,
      "variant" => variant
    }

    case Map.get(feature, "metadata") do
      metadata when metadata in [nil, %{}] -> result
      metadata -> Map.put(result, "metadata", metadata)
    end
  end

  defp select_variant(feature, identity_key, variants, reason) do
    percentage =
      Flagsmith.Engine.percentage_from_ids([to_str(Map.get(feature, "key")), identity_key])

    variants
    |> Enum.sort_by(&Map.get(&1, "priority"))
    |> Enum.reduce_while(0, fn %{"weight" => weight} = variant, start ->
      limit = weight + start

      case start <= percentage and percentage < limit do
        true ->
          {:halt,
           {Map.get(variant, "value"), Map.get(variant, "key"), "SPLIT; weight=#{to_str(weight)}"}}

        false ->
          {:cont, limit}
      end
    end)
    |> case do
      limit when is_number(limit) -> {Map.get(feature, "value"), "control", reason}
      selected -> selected
    end
  end

  defp read_flag(evaluation, state, feature_name) do
    case state.resolved do
      %{^feature_name => flag} ->
        {flag, state}

      _ ->
        state = resolve_feature(evaluation, %{state | used: true}, feature_name)
        {state.resolved[feature_name], state}
    end
  end

  defp resolve_feature(evaluation, %{resolving: resolving} = state, feature_name) do
    cond do
      feature_name in resolving ->
        cycle = [feature_name | Enum.take_while(resolving, &(&1 != feature_name))]

        %{
          state
          | cyclic: MapSet.union(state.cyclic, MapSet.new(cycle)),
            cycle_hits: state.cycle_hits + 1
        }

      not is_map_key(evaluation.features_by_key, feature_name) ->
        state

      true ->
        {override, state} =
          segment_override(
            evaluation,
            %{state | resolving: [feature_name | resolving]},
            feature_name
          )

        state = %{state | resolving: resolving}

        cond do
          feature_name in state.cyclic ->
            state

          override ->
            {%{feature: feature}, segment_name} = override
            flag = flag_result(evaluation, feature, "TARGETING_MATCH; segment=#{segment_name}")
            put_in(state, [:resolved, feature_name], flag)

          true ->
            feature = evaluation.features_by_key[feature_name]
            flag = flag_result(evaluation, feature, fallback_reason(evaluation, feature_name))
            put_in(state, [:resolved, feature_name], flag)
        end
    end
  end

  defp segment_override(evaluation, state, feature_name) do
    evaluation.segment_keys_by_feature_name
    |> Map.get(feature_name, [])
    |> Enum.reduce({nil, state}, fn segment_key, {override, state} ->
      case matches_segment?(evaluation, state, segment_key) do
        {false, state} ->
          {override, state}

        {true, state} ->
          segment = evaluation.segments_by_key[segment_key]

          override =
            segment.overrides
            |> Enum.filter(&(&1.name == feature_name))
            |> Enum.reduce(override, fn candidate, override ->
              case override == nil or candidate.priority < elem(override, 0).priority do
                true -> {candidate, segment.name}
                false -> override
              end
            end)

          {override, state}
      end
    end)
  end

  defp matches_segment?(evaluation, state, segment_key) do
    case state.segment_matches do
      %{^segment_key => matches} ->
        {matches, state}

      _ ->
        cycle_hits = state.cycle_hits
        segment = evaluation.segments_by_key[segment_key]
        {matches, state} = context_in_segment?(evaluation, state, segment)

        case state.cycle_hits != cycle_hits do
          # a verdict resting on an unresolvable flag is not a match, nor memoised
          true -> {false, state}
          false -> {matches, put_in(state, [:segment_matches, segment_key], matches)}
        end
    end
  end

  defp context_in_segment?(_evaluation, state, %{rules: nil}), do: {false, state}

  defp context_in_segment?(evaluation, state, %{rules: rules}),
    do: all(rules, state, &rule_matches?(evaluation, &2, &1))

  defp rule_matches?(_evaluation, state, :invalid), do: {false, state}

  defp rule_matches?(evaluation, state, {type, conditions, rules}) do
    {matches_conditions, state} =
      matching(type, conditions, state, &condition_matches?(evaluation, &2, &1))

    {matches_rules, state} = matching(type, rules, state, &rule_matches?(evaluation, &2, &1))
    {matches_conditions and matches_rules, state}
  end

  defp matching(_type, [], state, _fun), do: {true, state}
  defp matching("ALL", items, state, fun), do: all(items, state, fun)
  defp matching("ANY", items, state, fun), do: any(items, state, fun)

  defp matching("NONE", items, state, fun) do
    {matches, state} = any(items, state, fun)
    {not matches, state}
  end

  defp all([], state, _fun), do: {true, state}

  defp all([item | items], state, fun) do
    case fun.(item, state) do
      {true, state} -> all(items, state, fun)
      {false, _state} = result -> result
    end
  end

  defp any([], state, _fun), do: {false, state}

  defp any([item | items], state, fun) do
    case fun.(item, state) do
      {true, _state} = result -> result
      {false, state} -> any(items, state, fun)
    end
  end

  defp condition_matches?(evaluation, state, {operator, property, value}) do
    {context_value, state} = get_context_value(evaluation, state, property)
    {matches_condition?(operator, value, context_value), state}
  end

  defp matches_condition?("IN", values, context_value) do
    # Guard against comparing boolean values to numeric strings.
    context_value =
      case is_integer(context_value) do
        true -> Integer.to_string(context_value)
        false -> context_value
      end

    is_binary(context_value) and MapSet.member?(values, context_value)
  end

  defp matches_condition?("PERCENTAGE_SPLIT", _value, nil), do: false

  defp matches_condition?("PERCENTAGE_SPLIT", {{:ok, float}, segment_key}, context_value),
    do: Flagsmith.Engine.percentage_from_ids([segment_key, to_str(context_value)]) <= float

  defp matches_condition?("PERCENTAGE_SPLIT", _value, _context_value), do: false
  defp matches_condition?("IS_NOT_SET", _value, context_value), do: is_nil(context_value)
  defp matches_condition?("IS_SET", _value, context_value), do: not is_nil(context_value)
  defp matches_condition?(_operator, _value, nil), do: false

  defp matches_condition?("NOT_CONTAINS", value, context_value),
    do: is_binary(context_value) and not String.contains?(context_value, value)

  defp matches_condition?("REGEX", {:ok, regex}, context_value),
    do: :re.run(to_str(context_value), regex, [:anchored, capture: :none]) == :match

  defp matches_condition?("MODULO", {:ok, divisor, remainder}, context_value)
       when is_number(context_value),
       do: modulo(context_value, divisor) == remainder

  defp matches_condition?(operator, %{version: version} = value, context_value)
       when operator in @comparison_operators do
    case is_binary(context_value) and version != nil do
      true ->
        with {:ok, context_version} <- Version.parse(context_value),
             {:ok, segment_version} <- version do
          compare_versions(operator, Version.compare(context_version, segment_version))
        else
          _ -> false
        end

      false ->
        case cast_to_type_of(context_value, value) do
          {:ok, match_value} -> compare(operator, context_value, match_value)
          :error -> false
        end
    end
  end

  defp matches_condition?(_operator, _value, _context_value), do: false

  defp compare_versions("EQUAL", order), do: order == :eq
  defp compare_versions("NOT_EQUAL", order), do: order != :eq
  defp compare_versions("GREATER_THAN", order), do: order == :gt
  defp compare_versions("GREATER_THAN_INCLUSIVE", order), do: order in [:gt, :eq]
  defp compare_versions("LESS_THAN", order), do: order == :lt
  defp compare_versions("LESS_THAN_INCLUSIVE", order), do: order in [:lt, :eq]
  defp compare_versions(_, _), do: false

  defp compare("EQUAL", context_value, match_value), do: context_value == match_value
  defp compare("NOT_EQUAL", context_value, match_value), do: context_value != match_value
  defp compare("GREATER_THAN", context_value, match_value), do: context_value > match_value

  defp compare("GREATER_THAN_INCLUSIVE", context_value, match_value),
    do: context_value >= match_value

  defp compare("LESS_THAN", context_value, match_value), do: context_value < match_value

  defp compare("LESS_THAN_INCLUSIVE", context_value, match_value),
    do: context_value <= match_value

  defp compare("CONTAINS", context_value, match_value)
       when is_binary(context_value) and is_binary(match_value),
       do: String.contains?(context_value, match_value)

  defp compare(_, _, _), do: false

  defp cast_to_type_of(context_value, value) when is_boolean(context_value),
    do: {:ok, value.value not in ["False", "false"]}

  defp cast_to_type_of(context_value, value) when is_integer(context_value),
    do: parse_integer(value.value)

  defp cast_to_type_of(context_value, value) when is_float(context_value),
    do: parse_float(value.value)

  defp cast_to_type_of(_context_value, value), do: {:ok, value.string}

  defp semver?(value), do: is_binary(value) and String.ends_with?(value, ":semver")

  defp in_values(values) when is_list(values), do: MapSet.new(values, &to_str/1)

  defp in_values("[" <> _ = values) do
    case Jason.decode(values) do
      {:ok, decoded} when is_list(decoded) -> MapSet.new(decoded, &to_str/1)
      _ -> MapSet.new(String.split(values, ","))
    end
  end

  defp in_values(values) when is_binary(values), do: MapSet.new(String.split(values, ","))
  defp in_values(_), do: MapSet.new()

  # floored, as in Python
  defp modulo(dividend, divisor) do
    remainder = :math.fmod(dividend, divisor)

    case remainder != 0 and remainder < 0 != divisor < 0 do
      true -> remainder + divisor
      false -> remainder
    end
  end

  defp get_context_value(evaluation, state, :identity_key), do: {evaluation.identity_key, state}

  defp get_context_value(evaluation, state, {:trait, property}),
    do: {to_context_value(trait_value(evaluation, property)), state}

  defp get_context_value(evaluation, state, {:path, property, segments}) do
    case trait_value(evaluation, property) do
      nil ->
        {value, state} = query(evaluation, state, segments)
        {to_context_value(value), state}

      value ->
        {to_context_value(value), state}
    end
  end

  defp trait_value(%{traits: traits}, trait_key) do
    case traits do
      %{^trait_key => value} -> value
      _ -> nil
    end
  end

  defp query(evaluation, state, [{:name, "flags"}, {:name, feature_name} | segments]) do
    {flag, state} = read_flag(evaluation, state, feature_name)
    {find_value(flag, segments), state}
  end

  defp query(_evaluation, state, [{:name, "flags"} | segments]),
    do: {find_value(state.resolved, segments), state}

  defp query(evaluation, state, segments),
    do: {find_value(evaluation.context, segments), state}

  defp find_value(nil, _segments), do: nil

  defp find_value(data, segments) do
    case JSONPath.find_one(data, segments) do
      {:ok, value} when is_binary(value) or is_number(value) or is_boolean(value) -> value
      _ -> nil
    end
  end

  # number-like strings are coerced to numbers
  defp to_context_value(value) when is_binary(value) do
    case number_kind(value) do
      :integer -> String.to_integer(value)
      :float -> String.to_float(value)
      nil -> value
    end
  end

  defp to_context_value(value) when is_number(value) or is_boolean(value) or is_nil(value),
    do: value

  defp to_context_value(%Decimal{exp: 0} = value), do: Decimal.to_integer(value)
  defp to_context_value(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_context_value(value), do: to_str(value)

  # as matching ~r/^-?[0-9]+(\.[0-9]+)?$/, without a trailing newline
  defp number_kind("-" <> digits), do: number_kind(digits)
  defp number_kind(<<c, _::binary>> = digits) when c in ?0..?9, do: integer_digits(digits)
  defp number_kind(_), do: nil

  defp integer_digits(<<c, rest::binary>>) when c in ?0..?9, do: integer_digits(rest)
  defp integer_digits(""), do: :integer
  defp integer_digits(<<?., c, rest::binary>>) when c in ?0..?9, do: fraction_digits(rest)
  defp integer_digits(_), do: nil

  defp fraction_digits(<<c, rest::binary>>) when c in ?0..?9, do: fraction_digits(rest)
  defp fraction_digits(""), do: :float
  defp fraction_digits(_), do: nil

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end

  defp parse_integer(_), do: :error

  defp parse_float(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {float, ""} -> {:ok, float}
      _ -> :error
    end
  end

  defp parse_float(_), do: :error

  # as Python's `str`
  defp to_str(value) when is_binary(value), do: value
  defp to_str(true), do: "True"
  defp to_str(false), do: "False"
  defp to_str(nil), do: "None"
  defp to_str(value) when is_integer(value), do: Integer.to_string(value)
  defp to_str(value) when is_float(value), do: Float.to_string(value)
  defp to_str(value) when is_atom(value), do: Atom.to_string(value)
  defp to_str(%Version{} = value), do: Version.to_string(value)
  defp to_str(value), do: inspect(value)
end
