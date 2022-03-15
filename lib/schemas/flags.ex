defmodule Flagsmith.Schemas.Flags do
  use TypedEctoSchema

  alias Flagsmith.Configuration

  @primary_key false
  typed_embedded_schema do
    field(:flags, :map, default: %{})
    field(:__configuration__, :map)
  end

  @spec new(flags_map :: map(), config :: Configuration.t()) :: __MODULE__.t()
  def new(flags_map, %Configuration{} = config),
    do: %__MODULE__{flags: flags_map, __configuration__: config}
end
