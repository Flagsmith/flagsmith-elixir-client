defmodule Flagsmith.Schemas.Types.Operator do
  use TypedEnum,
    values: [
      :NOT_CONTAINS,
      :REGEX,
      :EQUAL,
      :GREATER_THAN,
      :GREATER_THAN_INCLUSIVE,
      :LESS_THAN,
      :LESS_THAN_INCLUSIVE,
      :NOT_EQUAL,
      :CONTAINS,
      :PERCENTAGE_SPLIT
    ]
end
