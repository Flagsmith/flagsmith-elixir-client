defmodule Flagsmith.Schemas.Features.Feature do
  use TypedEctoSchema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema representing a Flagsmith base feature definition. This differs from the
  `t:Flagsmith.Schemas.Environment.Feature.t/0` in the fields that make it up.
  """

  @primary_key false
  typed_embedded_schema do
    field(:created_date, :utc_datetime)
    field(:default_enabled, :boolean)
    field(:description, :string)
    field(:id, :integer)
    field(:initial_value, :string)
    field(:name, :string)
    field(:type, :string)
  end

  @doc false
  @spec changeset(map()) :: Ecto.Changeset.t()
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [
      :type,
      :name,
      :initial_value,
      :id,
      :description,
      :default_enabled,
      :created_date
    ])
    |> validate_required([:name])
  end
end
