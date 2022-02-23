defmodule FlagsmithEngine do
  alias Flagsmith.Schemas.{
    Environment,
    Traits,
    Segments,
    Identity,
    Features
  }

  @moduledoc """
  Documentation for `FlagsmithEngine`.
  """

  @api_version "v1"
  @default_url "https://api.flagsmith.com/api/#{@api_version}/"

  @doc """
  Returns the base url for the target flagsmith instance if provided, defaulting to
  the public API url.
  """
  @spec api_url() :: String.t()
  def api_url(),
    do: Application.get_env(:flagsmith_engine, :api_url, @default_url)

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
  Get a specific feature state for a given feature_name for a given identity and
  environment.
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
        } = identity,
        %Segments.Segment{id: segment_id, rules: rules} = segment,
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

  def percentage_from_ids(original_ids, iterations \\ 1) do
    with {_, as_strings} <- {:strings, Enum.map(original_ids, &"#{&1}")},
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

  def traits_match_segment_condition(
        traits,
        %Segments.Segment.Condition{operator: operator, value: value} = condition,
        segment_id,
        identifier,
        _iterations
      ) do
    Enum.all?(traits, fn %Traits.Trait{
                           trait_key: t_key,
                           trait_value: t_value
                         } ->
      trait_match(operator, value, t_key, t_value)
    end)
  end

  def trait_match(:NOT_CONTAINS, value, _t_key, t_value),
    do: value not in t_value

  def trait_match(:CONTAINS, value, _t_key, t_value),
    do: value in t_value

  def trait_match(:REGEX, value, _t_key, t_value),
    do: value == t_value

  def trait_match(:GREATER_THAN, value, _t_key, t_value),
    do: value > t_value

  def trait_match(:GREATER_THAN_INCLUSIVE, value, _t_key, t_value),
    do: value >= t_value

  def trait_match(:LESS_THAN, value, _t_key, t_value),
    do: value < t_value

  def trait_match(:LESS_THAN_INCLUSIVE, value, _t_key, t_value),
    do: value <= t_value

  def trait_match(:EQUAL, value, _t_key, t_value),
    do: value == t_value

  def trait_match(:NOT_EQUAL, value, _t_key, t_value),
    do: value != t_value

  @doc """
  Returns all feature flags.
  """
  @spec get_features() :: list(Features.FeatureState.t())
  def get_features(identity \\ nil, ets \\ FlagsmithEngine.Poller) do
    :ets.select(ets, [
      {
        {:_, :_, :_, :_, :"$1", :_, :"$3"},
        maybe_add_identity([], identity),
        [:"$3"]
      }
    ])
  end

  @doc """
  Returns a feature by name, if none or more than one feature is found, it returns
  an error.
  An optional second argument can be passed to restrict the result to a given 
  identity.
  Lastly, if the Poller was started with custom name for the ETS table (maybe multiple
  instances of Flagsmith) then that name can be passed as the 3rd argument, in order
  to fetch the feature from that table instead of the default one.
  """
  @spec get_feature(name :: String.t(), identity :: String.t() | nil, ets_table_name :: atom()) ::
          {:ok, Features.FeatureState.t()}
          | {:error, :not_found}
          | {:error, {:more_than_one, list(Features.FeatureState.t())}}
  def get_feature(name, identity \\ nil, ets \\ FlagsmithEngine.Poller) do
    :ets.select(
      ets,
      [
        {
          {:_, :_, :_, :_, :"$1", :"$2", :"$3"},
          maybe_add_identity([{:==, :"$2", name}], identity),
          [:"$3"]
        }
      ]
    )
    |> case do
      [h] -> {:ok, h}
      [] -> {:error, :not_found}
      too_many -> {:error, {:more_than_one, too_many}}
    end
  end

  @doc """
  Returns the value of a feature by name, if none or more than one feature is found, 
  it returns an error.
  An optional second argument can be passed to restrict the result to a given 
  identity.
  Lastly, if the Poller was started with custom name for the ETS table (maybe multiple
  instances of Flagsmith) then that name can be passed as the 3rd argument, in order
  to fetch the feature from that table instead of the default one.
  """
  @spec get_feature_value(
          name :: String.t(),
          identity :: String.t() | nil,
          ets_table_name :: atom()
        ) ::
          {:ok, Features.FeatureState.t()}
          | {:error, :not_found}
          | {:error, {:more_than_one, list(Features.FeatureState.t())}}
  def get_feature_value(name, identity \\ nil, ets \\ FlagsmithEngine.Poller) do
    :ets.select(
      ets,
      [
        {
          {:_, :_, :_, :_, :"$1", :"$2", :"$3"},
          maybe_add_identity([{:==, :"$2", name}], identity),
          [:"$3"]
        }
      ]
    )
    |> case do
      [%{feature_state_value: value}] -> {:ok, value}
      [] -> {:error, :not_found}
      too_many -> {:error, {:more_than_one, too_many}}
    end
  end

  defp maybe_add_identity(clauses, identity) do
    case identity do
      nil -> clauses
      _ -> [{:==, :"$1", identity} | clauses]
    end
  end
end
