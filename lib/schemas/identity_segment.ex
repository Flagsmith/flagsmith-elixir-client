defmodule Flagsmith.Schemas.Segments.IdentitySegment do
  use TypedEctoSchema
  import Ecto.Changeset

  alias Flagsmith.Schemas.Environment

  @moduledoc """
  Ecto schema representing a Flagsmith Identity Segment.
  """

  @primary_key {:id, :id, autogenerate: false}
  typed_embedded_schema do
    field(:name, :string)
  end

  @doc false
  @spec from_segment(Flagsmith.Schemas.Segments.Segment.t()) :: __MODULE__.t()
  def from_segment(%Flagsmith.Schemas.Segments.Segment{id: id, name: name}),
    do: %__MODULE__{id: id, name: name}
end
