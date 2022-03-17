defmodule Flagsmith.Schemas.Environment do
  use TypedEctoSchema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema representing a Flagsmith Environment definition.
  """

  @primary_key {:id, :id, autogenerate: false}
  typed_embedded_schema do
    field(:api_key, :string)
    embeds_many(:feature_states, __MODULE__.FeatureState)
    embeds_one(:project, __MODULE__.Project)
    embeds_one(:amplitude_config, __MODULE__.Integration)
    embeds_one(:segment_config, __MODULE__.Integration)
    embeds_one(:mixpanel_config, __MODULE__.Integration)
    embeds_one(:heap_config, __MODULE__.Integration)

    field(:__configuration__, :map)
  end

  @doc false
  @spec changeset(map()) :: Ecto.Changeset.t()
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, [:api_key, :id])
    |> cast_embed(:feature_states)
    |> cast_embed(:project)
    |> cast_embed(:amplitude_config)
    |> cast_embed(:segment_config)
    |> cast_embed(:mixpanel_config)
    |> cast_embed(:heap_config)
  end

  @doc false
  @spec cast(map()) :: {:ok, __MODULE__.t()} | {:error, Ecto.Changeset.t()}
  def cast(json_map) do
    json_map
    |> changeset()
    |> apply_action(:insert)
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

  @doc false
  def add_client_config(%__MODULE__{} = struct, %Flagsmith.Configuration{} = config),
    do: %{struct | __configuration__: config}
end
