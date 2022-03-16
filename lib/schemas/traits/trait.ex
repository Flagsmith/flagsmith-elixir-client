defmodule Flagsmith.Schemas.Traits.Trait do
  use TypedEctoSchema
  import Ecto.Changeset

  @type from_types :: __MODULE__.t() | map() | list(__MODULE__.t() | map())

  @moduledoc """
  Ecto schema representing a Flagsmith trait definition and helpers to cast responses
  from the api.
  """

  @derive {Jason.Encoder, only: [:trait_key, :trait_value]}

  @primary_key {:id, :id, autogenerate: false}
  typed_embedded_schema do
    field(:trait_key, :string)
    field(:trait_value, __MODULE__.Value)
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:trait_value, :trait_key, :id])
    |> validate_required([:trait_value, :trait_key])
  end

  @spec extract_trait_value(String.t(), list(__MODULE__.t())) ::
          {:ok, term()} | {:error, :not_found}
  def extract_trait_value(key, traits) do
    case Enum.find(traits, fn %{trait_key: t_key} -> key == t_key end) do
      %__MODULE__{trait_value: %{value: value}} -> {:ok, value}
      _ -> {:error, :not_found}
    end
  end

  @spec from(from_types()) :: list(__MODULE__.t()) | __MODULE__.t()
  def from(traits) when is_list(traits),
    do: Enum.map(traits, &from/1)

  def from(%__MODULE__{} = trait), do: trait

  def from(%{} = params) do
    %__MODULE__{}
    |> cast(params, [:trait_value, :trait_key, :id])
    |> validate_required([:trait_value])
    |> apply_changes()
  end

  @spec into_update_map(list(__MODULE__.t())) :: map()
  def into_update_map(traits) when is_list(traits) do
    traits
    |> Enum.reduce(%{}, fn %{trait_key: key, trait_value: value}, acc ->
      Map.put(acc, key, value)
    end)
  end
end
