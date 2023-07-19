defmodule Flagsmith.Schemas.Types.Operator do
  @moduledoc """
  Ecto Type representing an atom based enum mapping to the possible condition
  operators in Flagsmith.
  """

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
      :IS_SET,
      :IS_NOT_SET,
      :MODULO,
      :PERCENTAGE_SPLIT,
      :IN
    ]
end
