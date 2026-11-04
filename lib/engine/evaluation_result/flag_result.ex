defmodule Flagsmith.Engine.EvaluationResult.FlagResult do
  @moduledoc false

  @enforce_keys [:name, :enabled, :value, :reason, :variant]
  defstruct @enforce_keys ++ [metadata: nil]

  @type t :: %__MODULE__{
          name: String.t(),
          enabled: boolean(),
          value: String.t() | number() | boolean() | nil,
          reason: String.t(),
          variant: String.t() | nil,
          metadata: map() | nil
        }
end
