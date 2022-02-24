defmodule FlagsmithEngine.SegmentConditionsTest do
  use ExUnit.Case, async: true

  alias Flagsmith.Schemas.Traits.Trait

  @conditions [
    {:EQUAL, "bar", "bar", true},
    {:EQUAL, "bar", "baz", false},
    {:EQUAL, 1, "1", true},
    {:EQUAL, 1, "2", false},
    {:EQUAL, true, "True", true},
    {:EQUAL, false, "False", true},
    {:EQUAL, false, "True", false},
    {:EQUAL, true, "False", false},
    {:EQUAL, 1.23, "1.23", true},
    {:EQUAL, 1.23, "4.56", false},
    {:GREATER_THAN, 2, "1", true},
    {:GREATER_THAN, 1, "1", false},
    {:GREATER_THAN, 0, "1", false},
    {:GREATER_THAN, 2.1, "2.0", true},
    {:GREATER_THAN, 2.1, "2.1", false},
    {:GREATER_THAN, 2.0, "2.1", false},
    {:GREATER_THAN_INCLUSIVE, 2, "1", true},
    {:GREATER_THAN_INCLUSIVE, 1, "1", true},
    {:GREATER_THAN_INCLUSIVE, 0, "1", false},
    {:GREATER_THAN_INCLUSIVE, 2.1, "2.0", true},
    {:GREATER_THAN_INCLUSIVE, 2.1, "2.1", true},
    {:GREATER_THAN_INCLUSIVE, 2.0, "2.1", false},
    {:LESS_THAN, 1, "2", true},
    {:LESS_THAN, 1, "1", false},
    {:LESS_THAN, 1, "0", false},
    {:LESS_THAN, 2.0, "2.1", true},
    {:LESS_THAN, 2.1, "2.1", false},
    {:LESS_THAN, 2.1, "2.0", false},
    {:LESS_THAN_INCLUSIVE, 1, "2", true},
    {:LESS_THAN_INCLUSIVE, 1, "1", true},
    {:LESS_THAN_INCLUSIVE, 1, "0", false},
    {:LESS_THAN_INCLUSIVE, 2.0, "2.1", true},
    {:LESS_THAN_INCLUSIVE, 2.1, "2.1", true},
    {:LESS_THAN_INCLUSIVE, 2.1, "2.0", false},
    {:NOT_EQUAL, "bar", "baz", true},
    {:NOT_EQUAL, "bar", "bar", false},
    {:NOT_EQUAL, 1, "2", true},
    {:NOT_EQUAL, 1, "1", false},
    {:NOT_EQUAL, true, "false", true},
    {:NOT_EQUAL, false, "True", true},
    {:NOT_EQUAL, false, "false", false},
    {:NOT_EQUAL, true, "True", false},
    {:CONTAINS, "bar", "b", true},
    {:CONTAINS, "bar", "bar", true},
    {:CONTAINS, "bar", "baz", false},
    {:NOT_CONTAINS, "bar", "b", false},
    {:NOT_CONTAINS, "bar", "bar", false},
    {:NOT_CONTAINS, "bar", "baz", true},
    {:REGEX, "foo", "[a-z]+", true},
    {:REGEX, "FOO", "[a-z]+", false}
  ]

  test "all conditions" do
    assert Enum.all?(@conditions, fn {operator, trait_value, condition_value, expected} ->
             assert {:ok, value_form} = Trait.Value.cast(trait_value)

             assert expected == FlagsmithEngine.trait_match(operator, condition_value, value_form)
           end)
  end
end
