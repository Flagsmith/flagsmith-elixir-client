defmodule Flagsmith.Schemas.Flag do
  use TypedEctoSchema

  alias Flagsmith.Schemas.{Environment, Experiment, Features}

  @moduledoc """
  Ecto schema representing a Flagsmith Flag definition.
  """

  @primary_key {:feature_id, :id, autogenerate: false}
  typed_embedded_schema do
    field(:enabled, :boolean)
    field(:feature_name, :string)
    field(:value, :string)
    field(:variant, :string)
    embeds_one(:experiment, Experiment)
  end

  @doc false
  @spec from(Environment.FeatureState.t() | Features.FeatureState.t()) :: __MODULE__.t()
  def from(%Environment.FeatureState{
        enabled: enabled,
        feature_state_value: value,
        feature: %Environment.Feature{
          name: name,
          id: id
        }
      }) do
    %__MODULE__{
      enabled: enabled,
      feature_name: name,
      value: value,
      feature_id: id
    }
  end

  def from(%Features.FeatureState{
        enabled: enabled,
        feature_state_value: value,
        variant: variant,
        metadata: metadata,
        feature: %Features.Feature{
          name: name,
          id: id
        }
      }) do
    %__MODULE__{
      enabled: enabled,
      feature_name: name,
      value: value,
      feature_id: id,
      variant: variant,
      experiment: metadata && metadata.experiment
    }
  end
end
