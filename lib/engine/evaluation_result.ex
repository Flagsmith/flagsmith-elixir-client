defmodule Flagsmith.Engine.EvaluationResult do
  @moduledoc false

  # as specified by https://github.com/Flagsmith/flagsmith/blob/main/sdk/evaluation-result.json

  alias __MODULE__.{FlagResult, SegmentResult}

  @enforce_keys [:flags, :segments]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          flags: %{String.t() => FlagResult.t()},
          segments: list(SegmentResult.t())
        }
end
