defmodule Flagsmith.Schemas.Features.FeatureState do
  use TypedEctoSchema
  import Ecto.Changeset

  alias Flagsmith.Schemas.Types

  @moduledoc """
  Ecto schema representing a Flagsmith base feature state definition. This differs
  from the `t:Flagsmith.Schemas.Environment.FeatureState.t/0` in the fields that make
  it up.
  """

  @primary_key false
  typed_embedded_schema do
    field(:enabled, :boolean)
    field(:environment, :integer)
    field(:feature_segment, :integer)
    field(:feature_state_value, Types.AnyOf, types: [:string, :integer, :float, :boolean])
    field(:id, :integer)
    field(:identity, :integer)

    embeds_one(:feature, Flagsmith.Schemas.Features.Feature)
  end

  @doc false
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

  def from_response(something), do: something
end
