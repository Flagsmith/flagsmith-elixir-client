defmodule Flagsmith.Schemas.Segments.Segment.Rule do
  use TypedEctoSchema
  import Ecto.Changeset

  alias Flagsmith.Schemas.Segments.Segment

  @moduledoc """
  Ecto schema representing a Flagsmith Segment Rule definition.
  """

  @primary_key false
  typed_embedded_schema do
    field(:type, Flagsmith.Schemas.Types.Segment.Type)
    embeds_many(:rules, __MODULE__)
    embeds_many(:conditions, Segment.Condition)
  end

  @doc false
  @spec changeset(map()) :: Ecto.Changeset.t()
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:type])
    |> cast_embed(:rules)
    |> cast_embed(:conditions)
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
end
