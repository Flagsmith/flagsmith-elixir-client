defmodule Flagsmith.Engine.EvaluationResult.SegmentResult do
  @moduledoc false

  @enforce_keys [:name]
  defstruct @enforce_keys ++ [metadata: nil]

  @type t :: %__MODULE__{
          name: String.t(),
          metadata: map() | nil
        }
end
