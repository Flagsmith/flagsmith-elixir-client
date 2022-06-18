defmodule Flagsmith.Schemas.Identity do
  use TypedEctoSchema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema representing an object containing a Flagsmith identity with
  flags and traits.
  """

  @primary_key false
  typed_embedded_schema do
    field(:django_id, :integer)
    field(:identifier, :string)
    field(:environment_key, :string)
    embeds_many(:flags, Flagsmith.Schemas.Features.FeatureState)
    embeds_many(:traits, Flagsmith.Schemas.Traits.Trait)
  end

  @doc false
  @spec changeset(map()) :: Ecto.Changeset.t()
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:identifier, :environment_key, :django_id])
    |> validate_required([:identifier])
    |> cast_embed(:traits)
    |> cast_embed(:flags)
  end

  @doc false
  @spec from_id_traits(
          identifier :: String.t(),
          Flagsmith.Schemas.Traits.Trait.from_types(),
          environment_key :: nil | String.t()
        ) :: __MODULE__.t()
  def from_id_traits(identifier, traits, environment_key \\ nil),
    do: %__MODULE__{
      identifier: identifier,
      environment_key: environment_key,
      traits: Flagsmith.Schemas.Traits.Trait.from(traits)
    }

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

  @doc false
  @spec set_env_key(__MODULE__.t(), Flagsmith.Schemas.Environment.t() | String.t()) ::
          __MODULE__.t()
  def set_env_key(%__MODULE__{} = struct, %Flagsmith.Schemas.Environment{api_key: environment_key})
      when is_binary(environment_key),
      do: set_env_key(struct, environment_key)

  def set_env_key(%__MODULE__{} = struct, environment_key) when is_binary(environment_key),
    do: %{struct | environment_key: environment_key}

  @doc false
  @spec composite_key(__MODULE__.t()) :: String.t() | non_neg_integer()
  def composite_key(%__MODULE__{django_id: django_id})
      when is_integer(django_id),
      do: django_id

  def composite_key(%__MODULE__{identifier: identifier, environment_key: environment_key})
      when is_binary(environment_key),
      do: "#{environment_key}_#{identifier}"

  @doc false
  @spec composite_key(__MODULE__.t(), String.t()) :: String.t()
  def composite_key(%__MODULE__{identifier: identifier}, environment_key)
      when is_binary(environment_key),
      do: "#{environment_key}_#{identifier}"
end
