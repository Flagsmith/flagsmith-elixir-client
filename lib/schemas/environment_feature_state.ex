defmodule Flagsmith.Schemas.Environment.FeatureState do
  use TypedEctoSchema
  import Ecto.Changeset

  alias Flagsmith.Schemas.Environment

  @moduledoc """
  Ecto schema representing a Flagsmith environment feature definition and helpers
  to cast responses from the api.
  """

  @primary_key {:featurestate_uuid, :binary_id, autogenerate: false}
  typed_embedded_schema do
    field(:enabled, :boolean)
    field(:django_id, :integer)

    field(:feature_state_value, :string)

    embeds_one(:feature, Environment.Feature)

    embeds_many(:multivariate_feature_state_values, Environment.MultivariateFeatureStateValue)
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:featurestate_uuid, :enabled, :django_id, :feature_state_value])
    |> cast_embed(:feature)
    |> cast_embed(:multivariate_feature_state_values)
  end

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
end
