defmodule Flagsmith.Schemas.Experiment do
  use TypedEctoSchema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema representing the running Flagsmith experiment a flag was evaluated
  under, and whether the identity is enrolled in it.
  """

  @primary_key false
  typed_embedded_schema do
    field(:id, :integer)
    field(:name, :string)
    field(:in_experiment, :boolean, default: false)
  end

  @doc false
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params),
    do: cast(struct, params, [:id, :name, :in_experiment])
end
