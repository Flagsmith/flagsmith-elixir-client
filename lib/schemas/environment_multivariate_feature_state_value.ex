defmodule Flagsmith.Schemas.Environment.MultivariateFeatureStateValue do
  use TypedEctoSchema
  import Ecto.Changeset

  alias Flagsmith.Schemas.Environment

  @moduledoc """
  Ecto schema representing a Flagsmith environment feature definition and helpers
  to cast responses from the api.
  """

  @primary_key {:id, :id, autogenerate: false}
  typed_embedded_schema do
    field(:percentage_allocation, :float)
    field(:mv_fs_value_uuid, :binary_id)

    embeds_one(:multivariate_feature_option, Environment.MultivariateFeatureOption)
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:id, :percentage_allocation, :mv_fs_value_uuid])
    |> cast_embed(:multivariate_feature_option)
  end

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
