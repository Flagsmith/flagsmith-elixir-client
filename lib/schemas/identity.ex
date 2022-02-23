defmodule Flagsmith.Schemas.Identity do
  use TypedEctoSchema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema representing an object containing Flagsmith's flags and traits associated
  with an identity and helpers to cast responses from the api.
  """

  @primary_key false
  typed_embedded_schema do
    field(:identifier, :string)
    embeds_many(:flags, Flagsmith.Schemas.Identity.FeatureState)
    embeds_many(:traits, Flagsmith.Schemas.Traits.Trait)
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:identifier])
    |> validate_required([:identifier])
    |> cast_embed(:traits)
    |> cast_embed(:flags)
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
