defmodule Flagsmith.Schemas.Types.Segment.Type do
  use TypedEnum,
    values: [
      :ALL,
      :ANY,
      :NONE
    ]
end
