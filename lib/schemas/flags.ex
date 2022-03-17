defmodule Flagsmith.Schemas.Flags do
  use TypedEctoSchema

  alias Flagsmith.Configuration

  @moduledoc """
  Ecto schema representing a Flagsmith Flags structure, containing a map of ids to
  flags, and a client configuration field.
  """

  @primary_key false
  typed_embedded_schema do
    field(:flags, :map, default: %{})
    field(:__configuration__, :map)
  end

  @doc false
  @spec new(flags_map :: map(), config :: Configuration.t()) :: __MODULE__.t()
  def new(flags_map, %Configuration{} = config),
    do: %__MODULE__{flags: flags_map, __configuration__: config}
end
