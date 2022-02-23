defmodule Flagsmith.Schemas.Features.Feature do
  use TypedEctoSchema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema representing a Flagsmith feature definition and helpers to cast
  responses from the api.
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
