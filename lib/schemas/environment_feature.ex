defmodule Flagsmith.Schemas.Environment.Feature do
  use TypedEctoSchema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema representing a Flagsmith feature definition as represented in a
  full environment FeatureState.
  """

  @primary_key {:id, :id, autogenerate: false}
  typed_embedded_schema do
    field(:name, :string)
    field(:type, :string)
  end

  @doc false
  @spec changeset(map()) :: Ecto.Changeset.t()
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:id, :name, :type])
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
