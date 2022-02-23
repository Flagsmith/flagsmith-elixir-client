defmodule Flagsmith.Schemas.Features.FeatureState do
  use TypedEctoSchema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema representing a full Flagsmith feature definition and helpers to cast
  responses from the api.
  """

  @primary_key false
  typed_embedded_schema do
    field(:enabled, :boolean)

    field(:environment, :integer)

    field(:feature_segment, :integer)

    field(:feature_state_value, :string)

    field(:id, :integer)

    field(:identity, :integer)
    embeds_one(:feature, Flagsmith.Schemas.Features.Feature)
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [
      :identity,
      :id,
      :feature_state_value,
      :feature_segment,
      :environment,
      :enabled
    ])
    |> cast_embed(:feature, required: true)
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

  def from_response(something), do: something
end
