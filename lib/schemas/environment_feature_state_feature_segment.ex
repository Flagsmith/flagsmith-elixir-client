defmodule Flagsmith.Schemas.Environment.FeatureState.FeatureSegment do
  use TypedEctoSchema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema representing a FeatureState's Segment definition.
  """

  @primary_key false
  typed_embedded_schema do
    field(:priority, :integer, default: 0)
  end

  @doc false
  @spec changeset(map()) :: Ecto.Changeset.t()
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:priority])
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
