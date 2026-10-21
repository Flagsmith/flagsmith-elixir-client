defmodule Flagsmith.Engine.Evaluator do
  @moduledoc false

  alias Flagsmith.Engine.JSONPath

  @type context :: map()
  @type flag_result :: %{String.t() => term()}
  @type result :: %{String.t() => term()}

  @circular_dependency_reason "ERROR; code=CIRCULAR_DEPENDENCY"

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
    context = enrich_context(context)
    features = entries(context["features"])
    segments = entries(context["segments"])

    evaluation = %{
      context:
        Map.merge(context, %{"features" => Map.new(features), "segments" => Map.new(segments)}),
      features: Map.new(features),
      segments: Map.new(segments),
      identity_key: get_in(context, ["identity", "key"]),
      segment_keys_by_feature_name: segment_keys_by_feature_name(segments)
    }

    state = %{
      resolved: %{},
      cyclic: MapSet.new(),
      used: false,
      cycle_hits: 0,
      # most recent first
      resolving: [],
      segment_matches: %{}
    }

    {segment_results, segment_overrides, state} = evaluate_segments(evaluation, segments, state)
    flags = evaluate_features(evaluation, features, segment_overrides)

    flags =
      case state.used do
        false ->
          flags

        true ->
          # flags resolved for conditions are cycle-guarded, so take precedence
          state.cyclic
          |> Enum.reduce(Map.merge(flags, state.resolved), fn feature_name, flags ->
            case flags do
              %{^feature_name => flag} ->
                Map.put(flags, feature_name, %{flag | "reason" => @circular_dependency_reason})

              _ ->
                flags
            end
          end)
      end

    %{"flags" => flags, "segments" => segment_results}
  end

  defp enrich_context(%{"identity" => %{"identifier" => identifier} = identity} = context) do
    case identity["key"] do
      key when key in [nil, ""] ->
        put_in(context, ["identity", "key"], "#{context["environment"]["key"]}_#{identifier}")

      _ ->
        context
    end
  end

  defp enrich_context(context), do: context

  defp entries(nil), do: []
  defp entries(map) when is_map(map), do: Enum.to_list(map)
  defp entries(list) when is_list(list), do: list

  defp segment_keys_by_feature_name(segments) do
    segments
    |> Enum.flat_map(fn {segment_key, segment} ->
      Enum.map(overrides(segment), &{&1["name"], segment_key})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp overrides(segment), do: segment["overrides"] || []

  defp evaluate_segments(evaluation, segments, state) do
    {results, overrides, state, _cycle_hits} =
      Enum.reduce(segments, {[], %{}, state, state.cycle_hits}, fn {_key, segment},
                                                                   {results, overrides, state,
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
              Enum.reduce(overrides(segment), overrides, fn override, overrides ->
                name = override["name"]

                case wins_over?(override, overrides[name]) do
                  true -> Map.put(overrides, name, {override, segment["name"]})
                  false -> overrides
                end
              end)

            {[segment_result(segment) | results], overrides, state, cycle_hits}
        end
      end)

    {Enum.reverse(results), overrides, state}
  end

  defp segment_result(%{"name" => name} = segment) do
    case segment["metadata"] do
      metadata when metadata in [nil, %{}] -> %{"name" => name}
      metadata -> %{"name" => name, "metadata" => metadata}
    end
  end

  # lower priority wins, the first seen wins a tie
  defp wins_over?(_candidate, nil), do: true

  defp wins_over?(candidate, {incumbent, _segment_name}),
    do: priority(candidate) < priority(incumbent)

  defp priority(%{"priority" => :negative_infinity}), do: {0, 0}
  defp priority(%{"priority" => priority}) when is_number(priority), do: {1, priority}
  defp priority(_), do: {2, 0}

  defp evaluate_features(evaluation, features, segment_overrides) do
    Map.new(features, fn {_key, %{"name" => name} = feature} ->
      flag =
        case segment_overrides do
          %{^name => {override, segment_name}} ->
            flag_result(evaluation, override, "TARGETING_MATCH; segment=#{segment_name}")

          _ ->
            flag_result(evaluation, feature, fallback_reason(evaluation, name))
        end

      {name, flag}
    end)
  end

  defp fallback_reason(%{segment_keys_by_feature_name: keys}, name)
       when is_map_key(keys, name),
       do: "DEFAULT"

  defp fallback_reason(_, _), do: "STATIC"

  defp flag_result(evaluation, feature, reason) do
    {value, variant, reason} =
      case {evaluation.identity_key, feature["variants"]} do
        {key, [_ | _] = variants} when not is_nil(key) ->
          select_variant(feature, key, variants, reason)

        _ ->
          {feature["value"], nil, reason}
      end

    result = %{
      "enabled" => feature["enabled"],
      "name" => feature["name"],
      "reason" => reason,
      "value" => value,
      "variant" => variant
    }

    case feature["metadata"] do
      metadata when metadata in [nil, %{}] -> result
      metadata -> Map.put(result, "metadata", metadata)
    end
  end

  defp select_variant(feature, identity_key, variants, reason) do
    percentage = Flagsmith.Engine.percentage_from_ids([to_str(feature["key"]), identity_key])

    variants
    |> Enum.sort_by(& &1["priority"])
    |> Enum.reduce_while(0, fn %{"weight" => weight} = variant, start ->
      limit = weight + start

      case start <= percentage and percentage < limit do
        true ->
          {:halt, {variant["value"], variant["key"], "SPLIT; weight=#{to_str(weight)}"}}

        false ->
          {:cont, limit}
      end
    end)
    |> case do
      limit when is_number(limit) -> {feature["value"], "control", reason}
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

      not is_map_key(evaluation.features, feature_name) ->
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
            {feature, segment_name} = override
            flag = flag_result(evaluation, feature, "TARGETING_MATCH; segment=#{segment_name}")
            put_in(state, [:resolved, feature_name], flag)

          true ->
            feature = evaluation.features[feature_name]
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
          segment = evaluation.segments[segment_key]

          override =
            segment
            |> overrides()
            |> Enum.filter(&(&1["name"] == feature_name))
            |> Enum.reduce(override, fn candidate, override ->
              case wins_over?(candidate, override) do
                true -> {candidate, segment["name"]}
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
        segment = evaluation.segments[segment_key]
        {matches, state} = context_in_segment?(evaluation, state, segment)

        case state.cycle_hits != cycle_hits do
          # a verdict resting on an unresolvable flag is not a match, nor memoised
          true -> {false, state}
          false -> {matches, put_in(state, [:segment_matches, segment_key], matches)}
        end
    end
  end

  defp context_in_segment?(evaluation, state, %{"rules" => [_ | _] = rules} = segment) do
    all(rules, state, &rule_matches?(evaluation, &2, &1, segment["key"]))
  end

  defp context_in_segment?(_evaluation, state, _segment), do: {false, state}

  defp rule_matches?(evaluation, state, rule, segment_key) do
    case matching_function(rule["type"]) do
      nil ->
        {false, state}

      matching_function ->
        {matches_conditions, state} =
          case rule["conditions"] do
            [_ | _] = conditions ->
              matching_function.(
                conditions,
                state,
                &condition_matches?(evaluation, &2, &1, segment_key)
              )

            _ ->
              {true, state}
          end

        {matches_rules, state} =
          case rule["rules"] do
            [_ | _] = rules ->
              matching_function.(rules, state, &rule_matches?(evaluation, &2, &1, segment_key))

            _ ->
              {true, state}
          end

        {matches_conditions and matches_rules, state}
    end
  end

  defp matching_function("ALL"), do: &all/3
  defp matching_function("ANY"), do: &any/3
  defp matching_function("NONE"), do: &none/3
  defp matching_function(_), do: nil

  defp all(items, state, fun) do
    Enum.reduce_while(items, {true, state}, fn item, {_, state} ->
      case fun.(item, state) do
        {true, state} -> {:cont, {true, state}}
        {false, state} -> {:halt, {false, state}}
      end
    end)
  end

  defp any(items, state, fun) do
    Enum.reduce_while(items, {false, state}, fn item, {_, state} ->
      case fun.(item, state) do
        {true, state} -> {:halt, {true, state}}
        {false, state} -> {:cont, {false, state}}
      end
    end)
  end

  defp none(items, state, fun) do
    {matches, state} = any(items, state, fun)
    {not matches, state}
  end

  defp condition_matches?(evaluation, state, condition, segment_key) do
    property = condition["property"]
    operator = condition["operator"]

    {context_value, state} =
      case operator == "PERCENTAGE_SPLIT" and property in [nil, ""] do
        # legacy segments split on the identity key
        true -> {evaluation.identity_key, state}
        false -> get_context_value(evaluation, state, property || "")
      end

    {matches_condition?(operator, condition["value"], context_value, segment_key), state}
  end

  defp matches_condition?("IN", segment_value, context_value, _segment_key) do
    # Guard against comparing boolean values to numeric strings.
    context_value =
      case is_integer(context_value) do
        true -> Integer.to_string(context_value)
        false -> context_value
      end

    is_binary(context_value) and MapSet.member?(in_values(segment_value), context_value)
  end

  defp matches_condition?("PERCENTAGE_SPLIT", _segment_value, nil, _segment_key), do: false

  defp matches_condition?("PERCENTAGE_SPLIT", segment_value, context_value, segment_key) do
    case parse_float(segment_value) do
      {:ok, float} ->
        Flagsmith.Engine.percentage_from_ids([to_str(segment_key), to_str(context_value)]) <=
          float

      :error ->
        false
    end
  end

  defp matches_condition?("IS_NOT_SET", _segment_value, context_value, _segment_key),
    do: is_nil(context_value)

  defp matches_condition?("IS_SET", _segment_value, context_value, _segment_key),
    do: not is_nil(context_value)

  defp matches_condition?(_operator, _segment_value, nil, _segment_key), do: false

  defp matches_condition?("NOT_CONTAINS", segment_value, context_value, _segment_key),
    do: is_binary(context_value) and not String.contains?(context_value, to_str(segment_value))

  defp matches_condition?("REGEX", segment_value, context_value, _segment_key) do
    case :re.compile(to_str(segment_value), [:unicode, :ucp]) do
      {:ok, regex} ->
        :re.run(to_str(context_value), regex, [:anchored, capture: :none]) == :match

      {:error, _} ->
        false
    end
  end

  defp matches_condition?("MODULO", segment_value, context_value, _segment_key)
       when is_number(context_value) and is_binary(segment_value) do
    with [divisor, remainder] <- String.split(segment_value, "|"),
         {:ok, divisor} when divisor != 0 <- parse_float(divisor),
         {:ok, remainder} <- parse_float(remainder) do
      modulo(context_value, divisor) == remainder
    else
      _ -> false
    end
  end

  defp matches_condition?(operator, segment_value, context_value, _segment_key)
       when operator in [
              "EQUAL",
              "NOT_EQUAL",
              "GREATER_THAN",
              "GREATER_THAN_INCLUSIVE",
              "LESS_THAN",
              "LESS_THAN_INCLUSIVE",
              "CONTAINS"
            ] do
    case is_binary(context_value) and semver?(segment_value) do
      true ->
        with {:ok, context_version} <- Version.parse(context_value),
             {:ok, segment_version} <-
               Version.parse(String.replace_suffix(segment_value, ":semver", "")) do
          compare_versions(operator, Version.compare(context_version, segment_version))
        else
          _ -> false
        end

      false ->
        case cast_to_type_of(context_value, segment_value) do
          {:ok, match_value} -> compare(operator, context_value, match_value)
          :error -> false
        end
    end
  end

  defp matches_condition?(_operator, _segment_value, _context_value, _segment_key), do: false

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

  defp cast_to_type_of(context_value, segment_value) when is_boolean(context_value),
    do: {:ok, segment_value not in ["False", "false"]}

  defp cast_to_type_of(context_value, segment_value) when is_integer(context_value),
    do: parse_integer(segment_value)

  defp cast_to_type_of(context_value, segment_value) when is_float(context_value),
    do: parse_float(segment_value)

  defp cast_to_type_of(_context_value, segment_value), do: {:ok, to_str(segment_value)}

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

  defp get_context_value(evaluation, state, "$." <> _ = property) do
    with nil <- trait_value(evaluation, property),
         {:ok, segments} <- JSONPath.compile(property) do
      {value, state} = query(evaluation, state, segments)
      {to_context_value(value), state}
    else
      :error -> {nil, state}
      value -> {to_context_value(value), state}
    end
  end

  defp get_context_value(evaluation, state, property),
    do: {to_context_value(trait_value(evaluation, property)), state}

  defp trait_value(%{context: context}, trait_key) do
    case context do
      %{"identity" => %{"traits" => %{^trait_key => value}}} -> value
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

  @doc """
  Coerce a value to a context value: a string, number, boolean or nil.
  Number-like strings are coerced to numbers.
  """
  @spec to_context_value(term()) :: String.t() | number() | boolean() | nil
  def to_context_value(value) when is_binary(value) do
    cond do
      Regex.match?(~r/^-?[0-9]+$/, value) -> String.to_integer(value)
      Regex.match?(~r/^-?[0-9]+\.[0-9]+$/, value) -> String.to_float(value)
      true -> value
    end
  end

  def to_context_value(value) when is_number(value) or is_boolean(value) or is_nil(value),
    do: value

  def to_context_value(%Decimal{exp: 0} = value), do: Decimal.to_integer(value)
  def to_context_value(%Decimal{} = value), do: Decimal.to_float(value)
  def to_context_value(value), do: to_str(value)

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
