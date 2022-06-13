defmodule Flagsmith.Schemas.Environment.FeatureState do
  use TypedEctoSchema
  import Ecto.Changeset

  alias Flagsmith.Schemas.Environment

  @moduledoc """
  Ecto schema representing a Flagsmith full feature state definition (as represented 
  in the environment definition).
  """

  @primary_key {:featurestate_uuid, :binary_id, autogenerate: false}
  typed_embedded_schema do
    field(:enabled, :boolean)
    field(:django_id, :integer)

    field(:feature_state_value, :string)

    embeds_one(:feature, Environment.Feature)
    embeds_one(:feature_segment, __MODULE__.FeatureSegment)
    embeds_many(:multivariate_feature_state_values, Environment.MultivariateFeatureStateValue)
  end

  @doc false
  @spec changeset(map()) :: Ecto.Changeset.t()
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:featurestate_uuid, :enabled, :django_id, :feature_state_value])
    |> cast_embed(:feature)
    |> cast_embed(:feature_segment)
    |> cast_embed(:multivariate_feature_state_values)
  end

  @doc false
  @spec from_response(element :: map() | list(map())) :: __MODULE__.t() | any()
  def from_response(element) when is_map(element) do
    element
    |> changeset()
    |> apply_changes()
  end

  def from_response(elements) when is_list(elements) do
    Enum.map(elements, fn element ->
      element
      |> changeset()
      |> apply_changes()
    end)
  end

  def from_response(element), do: element

  @doc false
  def get_hashing_id(%__MODULE__{django_id: nil, featurestate_uuid: id}),
    do: id

  def get_hashing_id(%__MODULE__{django_id: django_id}),
    do: django_id

  def get_hashing_id(%{id: id}),
    do: id

  @doc false
  def extract_multivariate_value(%Environment.MultivariateFeatureStateValue{
        multivariate_feature_option: %Environment.MultivariateFeatureOption{
          value: value
        }
      }),
      do: {:ok, value}

  def extract_multivariate_value(_), do: {:error, :invalid_multivariate}

  @doc false
  def is_higher_priority?(%__MODULE__{feature_segment: fs_a}, %__MODULE__{feature_segment: fs_b}) do
    case {fs_a, fs_b} do
      {nil, nil} ->
        false

      {nil, _} ->
        false

      {_, nil} ->
        true

      {%__MODULE__.FeatureSegment{priority: priority_a},
       %__MODULE__.FeatureSegment{priority: priority_b}} ->
        priority_a < priority_b
    end
  end
end
