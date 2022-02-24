defmodule FlagsmithEngine do
  alias Flagsmith.Schemas.{
    Environment,
    Traits,
    Segments,
    Identity
  }

  alias Traits.Trait
  alias Flagsmith.Schemas.Types
  @condition_operators Flagsmith.Schemas.Types.Operator.values(:atoms)

  @moduledoc """
  Documentation for `FlagsmithEngine`.
  """

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
  Get the environment feature states.
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
  Get a specific feature state for a given feature_name in a given environment.
  """
  @spec get_environment_feature_state(Environment.t(), name :: String.t()) ::
          Environment.FeatureState.t() | nil
  def get_environment_feature_state(%Environment{feature_states: fs}, name),
    do: Enum.find(fs, fn %{feature: %{name: f_name}} -> f_name == name end)

  @doc """
  Get list of feature states for a given identity in a given environment.
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
        },
        %Identity{flags: identity_features} = identity,
        override_traits \\ []
      ) do
    with segment_features <- get_segment_features(segments, identity, override_traits),
         replaced <- replace_segment_features(fs, segment_features),
         final_features <- replace_identity_features(replaced, identity_features) do
      final_features
    end
  end

  @doc """
  Get feature state with a given feature_name for a given identity and environment.
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

  def get_segment_features(segments, identity, override_traits) do
    Enum.filter(segments, fn segment ->
      evaluate_identity_in_segment(identity, segment, override_traits)
    end)
  end

  def replace_segment_features(original, to_replace) do
    Enum.reduce(to_replace, original, fn %{name: replacement_name, feature_states: segment_fs},
                                         acc ->
      Enum.map(acc, fn %{feature: %{name: feature_name}} = flag ->
        case replacement_name == feature_name do
          true ->
            case Enum.reduce(segment_fs, nil, fn segment -> segment end) do
              nil -> flag
              replacement -> replacement
            end

          _ ->
            flag
        end
      end)
    end)
  end

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

  def evaluate_identity_in_segment(_, %Segments.Segment{rules: []}, _),
    do: false

  def evaluate_identity_in_segment(
        %Identity{
          identifier: identifier,
          traits: identity_traits
        },
        %Segments.Segment{id: segment_id, rules: rules},
        override_traits
      ) do
    traits =
      case override_traits do
        [_ | _] -> override_traits
        _ -> identity_traits
      end

    Enum.all?(rules, fn rule ->
      traits_match_segment_rule(traits, rule, segment_id, identifier)
    end)
  end

  def traits_match_segment_rule(
        traits,
        %Segments.Segment.Rule{rules: rules, conditions: conditions},
        segment_id,
        identifier
      ) do
    Enum.all?(conditions, fn condition ->
      traits_match_segment_condition(traits, condition, segment_id, identifier)
    end) and
      Enum.all?(rules, fn rule ->
        traits_match_segment_rule(traits, rule, segment_id, identifier)
      end)
  end

  def traits_match_segment_condition(traits, condition, segment_id, identifier, iterations \\ 1)

  def traits_match_segment_condition(
        traits,
        %Segments.Segment.Condition{operator: :PERCENTAGE_SPLIT, value: value} = condition,
        segment_id,
        identifier,
        iterations
      ) do
    with {_, {float, _}} <- {:float_parse, Float.parse(value)},
         {_, percentage} <-
           {:percentage, percentage_from_ids([segment_id, identifier], iterations)} do
      case percentage do
        100 ->
          traits_match_segment_condition(
            traits,
            condition,
            segment_id,
            identifier,
            iterations + 1
          )

        _ ->
          percentage <= float
      end
    else
      {_what, _} ->
        false
    end
  end

  def traits_match_segment_condition(
        traits,
        %Segments.Segment.Condition{operator: operator, value: value},
        _segment_id,
        _identifier,
        _iterations
      ) do
    Enum.all?(traits, fn %Traits.Trait{
                           trait_key: _t_key,
                           trait_value: t_value
                         } ->
      case cast_value(t_value, value) do
        {:ok, casted} ->
          trait_match(operator, casted, t_value)

        _ ->
          false
      end
    end)
  end

  def percentage_from_ids(original_ids, iterations \\ 1) do
    with {_, as_strings} <- {:strings, Enum.map(original_ids, &id_to_string/1)},
         {_, ids} <- {:ids, List.duplicate(as_strings, iterations)},
         {_, stringed} <- {:join, Enum.join(ids, ",")},
         {_, hashed} <- {:hash, :crypto.hash(:md5, stringed)},
         {_, hexed} <- {:hex, Base.hex_encode32(hashed)},
         {_, {int, _}} <- {:int_parse, Integer.parse(hexed, 32)} do
      Integer.mod(int, 9999) / 9998 * 100
    else
      {_, _} = error -> {:error, error}
    end
  end

  def id_to_string(ids) when is_list(ids), do: Enum.map(ids, &id_to_string/1)
  def id_to_string(int) when is_integer(int), do: Integer.to_string(int)
  def id_to_string(bin) when is_binary(bin), do: bin
  def id_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)

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
