defmodule Flagsmith.Schemas.Segments.Segment do
  use TypedEctoSchema
  import Ecto.Changeset

  alias Flagsmith.Schemas.Environment

  @moduledoc """
  Ecto schema representing a Flagsmith organisation definition and helpers
  to cast responses from the api.
  """

  @primary_key {:id, :id, autogenerate: false}
  typed_embedded_schema do
    field(:name, :string)
    embeds_many(:rules, __MODULE__.Rule)
    embeds_many(:feature_states, Environment.FeatureState)
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:id, :name])
    |> cast_embed(:feature_states)
    |> cast_embed(:rules)
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
