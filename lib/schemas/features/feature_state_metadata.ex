defmodule Flagsmith.Schemas.Features.FeatureState.Metadata do
  use TypedEctoSchema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema representing the additional, non-evaluation data Flagsmith returns
  with a feature state.
  """

  @primary_key false
  typed_embedded_schema do
    embeds_one(:experiment, Flagsmith.Schemas.Experiment)
  end

  @doc false
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    struct
    |> cast(params, [])
    |> cast_embed(:experiment)
  end
end
