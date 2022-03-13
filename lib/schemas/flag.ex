defmodule Flagsmith.Schemas.Flag do
  use TypedEctoSchema

  alias Flagsmith.Schemas.{Environment, Features}

  @moduledoc """
  Ecto schema representing a Flagsmith environment feature definition and helpers
  to cast responses from the api.
  """

  @primary_key {:feature_id, :id, autogenerate: false}
  typed_embedded_schema do
    field(:enabled, :boolean)
    field(:feature_name, :string)
    field(:value, :string)
  end

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
        feature: %Features.Feature{
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
end
