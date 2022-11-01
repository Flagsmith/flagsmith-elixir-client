defmodule Flagsmith.Schemas.Segments.IdentitySegment do
  use TypedEctoSchema

  alias Flagsmith.Schemas.Segments

  @moduledoc """
  Ecto schema representing a Flagsmith Identity Segment.
  """

  @primary_key {:id, :id, autogenerate: false}
  typed_embedded_schema do
    field(:name, :string)
  end

  @doc false
  @spec from_segment(Segments.Segment.t()) :: __MODULE__.t()
  def from_segment(%Segments.Segment{id: id, name: name}),
    do: %__MODULE__{id: id, name: name}
end
