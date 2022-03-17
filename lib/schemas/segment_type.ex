defmodule Flagsmith.Schemas.Types.Segment.Type do
  @moduledoc """
  Ecto type representing an enum for possible Segment type evaluation rules.
  """

  use TypedEnum,
    values: [
      :ALL,
      :ANY,
      :NONE
    ]

  @doc false
  def enum_matching_function(:ALL), do: &Enum.all?/2
  def enum_matching_function(:ANY), do: &Enum.any?/2
  def enum_matching_function(:NONE), do: &(!Enum.any?(&1, &2))
end
