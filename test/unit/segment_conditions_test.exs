defmodule Flagsmith.Engine.SegmentConditionsTest do
  use ExUnit.Case, async: true

  alias Flagsmith.Schemas.Traits.Trait
  alias Flagsmith.Schemas.Segments.Segment

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
    {:REGEX, "FOO", "[a-z]+", false},
    {:REGEX, "1.2.3", "\\d", true},
    {:IS_SET, nil, nil, false},
    {:IS_SET, "oi", nil, true},
    {:IS_NOT_SET, nil, nil, true},
    {:IS_NOT_SET, "oi", nil, false}
  ]

  test "all conditions" do
    assert Enum.all?(@conditions, fn {operator, trait_value, condition_value, expected} ->
             assert {:ok, value_form} = Trait.Value.cast(trait_value)

             assert expected ==
                      Flagsmith.Engine.trait_match(operator, condition_value, value_form)
           end)
  end

  @semver_conditions [
    {:EQUAL, "1.0.0", "1.0.0:semver", true},
    {:EQUAL, "1.0.0", "1.0.1:semver", false},
    {:NOT_EQUAL, "1.0.0", "1.0.0:semver", false},
    {:NOT_EQUAL, "1.0.0", "1.0.1:semver", true},
    {:GREATER_THAN, "1.0.1", "1.0.0:semver", true},
    {:GREATER_THAN, "1.0.0", "1.0.0-beta:semver", true},
    {:GREATER_THAN, "1.0.1", "1.2.0:semver", false},
    {:GREATER_THAN, "1.0.1", "1.0.1:semver", false},
    {:GREATER_THAN, "1.2.4", "1.2.3-pre.2+build.4:semver", true},
    {:LESS_THAN, "1.0.0", "1.0.1:semver", true},
    {:LESS_THAN, "1.0.0", "1.0.0:semver", false},
    {:LESS_THAN, "1.0.1", "1.0.0:semver", false},
    {:LESS_THAN, "1.0.0-rc.2", "1.0.0-rc.3:semver", true},
    {:GREATER_THAN_INCLUSIVE, "1.0.1", "1.0.0:semver", true},
    {:GREATER_THAN_INCLUSIVE, "1.0.1", "1.2.0:semver", false},
    {:GREATER_THAN_INCLUSIVE, "1.0.1", "1.0.1:semver", true},
    {:LESS_THAN_INCLUSIVE, "1.0.0", "1.0.1:semver", true},
    {:LESS_THAN_INCLUSIVE, "1.0.0", "1.0.0:semver", true},
    {:LESS_THAN_INCLUSIVE, "1.0.1", "1.0.0:semver", false}
  ]

  test "all semver conditions" do
    assert Enum.all?(@semver_conditions, fn {operator, trait_value, condition_value, expected} ->
             assert {:ok, value_form} = Trait.Value.cast(trait_value)

             assert expected ==
                      Flagsmith.Engine.trait_match(operator, condition_value, value_form)
           end)
  end

  @segment_rule_all %Segment.Rule{
    conditions: [],
    rules: [
      %Segment.Rule{
        conditions: [
          %Segment.Condition{
            operator: :EQUAL,
            property_: "test_true",
            value: "true"
          }
        ],
        rules: [],
        type: :ANY
      },
      %Segment.Rule{
        conditions: [
          %Segment.Condition{
            operator: :EQUAL,
            property_: "test_false",
            value: "false"
          }
        ],
        rules: [],
        type: :ANY
      }
    ],
    type: :ALL
  }

  @segment_rule_any %{@segment_rule_all | type: :ANY}
  @segment_rule_none %{@segment_rule_all | type: :NONE}

  test "Segment.Rule type :ALL" do
    traits_1 = [
      %Trait{
        trait_key: "test_true",
        trait_value: %Trait.Value{value: true, type: :boolean}
      },
      %Trait{
        trait_key: "test_false",
        trait_value: %Trait.Value{value: false, type: :boolean}
      }
    ]

    assert Flagsmith.Engine.traits_match_segment_rule(traits_1, @segment_rule_all, 1, 1)

    traits_2 = [
      %Trait{
        trait_key: "test_true",
        trait_value: %Trait.Value{value: false, type: :boolean}
      },
      %Trait{
        trait_key: "test_false",
        trait_value: %Trait.Value{value: false, type: :boolean}
      }
    ]

    refute Flagsmith.Engine.traits_match_segment_rule(traits_2, @segment_rule_all, 1, 1)
  end

  test "Segment.Rule type :ANY" do
    traits_1 = [
      %Trait{
        trait_key: "test_true",
        trait_value: %Trait.Value{value: false, type: :boolean}
      },
      %Trait{
        trait_key: "test_false",
        trait_value: %Trait.Value{value: false, type: :boolean}
      }
    ]

    assert Flagsmith.Engine.traits_match_segment_rule(traits_1, @segment_rule_any, 1, 1)

    traits_2 = [
      %Trait{
        trait_key: "test_true",
        trait_value: %Trait.Value{value: false, type: :boolean}
      },
      %Trait{
        trait_key: "test_false",
        trait_value: %Trait.Value{value: true, type: :boolean}
      }
    ]

    refute Flagsmith.Engine.traits_match_segment_rule(traits_2, @segment_rule_any, 1, 1)
  end

  test "Segment.Rule type :NONE" do
    traits_1 = [
      %Trait{
        trait_key: "test_true",
        trait_value: %Trait.Value{value: false, type: :boolean}
      },
      %Trait{
        trait_key: "test_false",
        trait_value: %Trait.Value{value: true, type: :boolean}
      }
    ]

    assert Flagsmith.Engine.traits_match_segment_rule(traits_1, @segment_rule_none, 1, 1)

    traits_2 = [
      %Trait{
        trait_key: "test_true",
        trait_value: %Trait.Value{value: true, type: :boolean}
      },
      %Trait{
        trait_key: "test_false",
        trait_value: %Trait.Value{value: false, type: :boolean}
      }
    ]

    refute Flagsmith.Engine.traits_match_segment_rule(traits_2, @segment_rule_none, 1, 1)
  end

  @segment_rule_nested_all %Segment.Rule{
    conditions: [],
    rules: [
      %Segment.Rule{
        conditions: [
          %Segment.Condition{
            operator: :EQUAL,
            property_: "test_true",
            value: "true"
          }
        ],
        rules: [
          %Segment.Rule{
            conditions: [
              %Segment.Condition{
                operator: :EQUAL,
                property_: "test_false",
                value: "false"
              }
            ],
            rules: [],
            type: :ALL
          }
        ],
        type: :ALL
      }
    ],
    type: :ALL
  }

  test "Segment.Rule type :ALL nested" do
    traits_1 = [
      %Trait{
        trait_key: "test_true",
        trait_value: %Trait.Value{value: true, type: :boolean}
      },
      %Trait{
        trait_key: "test_false",
        trait_value: %Trait.Value{value: false, type: :boolean}
      }
    ]

    assert Flagsmith.Engine.traits_match_segment_rule(traits_1, @segment_rule_nested_all, 1, 1)

    # test_false is in the inner rule condition, so for it to fail it means that rule
    # had to be evaluated, so we set its value as true to not match the condition
    traits_2 = [
      %Trait{
        trait_key: "test_true",
        trait_value: %Trait.Value{value: true, type: :boolean}
      },
      %Trait{
        trait_key: "test_false",
        trait_value: %Trait.Value{value: true, type: :boolean}
      }
    ]

    refute Flagsmith.Engine.traits_match_segment_rule(traits_2, @segment_rule_nested_all, 1, 1)
  end

  @segment_rule_nested_any %Segment.Rule{
    conditions: [],
    rules: [
      %Segment.Rule{
        conditions: [
          %Segment.Condition{
            operator: :EQUAL,
            property_: "test_true",
            value: "true"
          }
        ],
        rules: [
          %Segment.Rule{
            conditions: [
              %Segment.Condition{
                operator: :EQUAL,
                property_: "test_false",
                value: "false"
              },
              %Segment.Condition{
                operator: :EQUAL,
                property_: "test_false",
                value: "true"
              }
            ],
            rules: [],
            type: :ANY
          }
        ],
        type: :ALL
      }
    ],
    type: :ALL
  }

  test "Segment.Rule type :ANY nested" do
    # test_false is in the inner rule condition, there's two inner conditions for the
    # it, both equals for false and true, so it should always test true with `ANY`
    traits_1 = [
      %Trait{
        trait_key: "test_true",
        trait_value: %Trait.Value{value: true, type: :boolean}
      },
      %Trait{
        trait_key: "test_false",
        trait_value: %Trait.Value{value: true, type: :boolean}
      }
    ]

    assert Flagsmith.Engine.traits_match_segment_rule(traits_1, @segment_rule_nested_any, 1, 1)

    # now with false, so we can test that either condition works
    traits_2 = [
      %Trait{
        trait_key: "test_true",
        trait_value: %Trait.Value{value: true, type: :boolean}
      },
      %Trait{
        trait_key: "test_false",
        trait_value: %Trait.Value{value: false, type: :boolean}
      }
    ]

    assert Flagsmith.Engine.traits_match_segment_rule(traits_2, @segment_rule_nested_any, 1, 1)

    # test_false is in the inner rule condition, so for it to fail it means that rule
    # had to be evaluated, so we set its value as a non matching type
    traits_3 = [
      %Trait{
        trait_key: "test_true",
        trait_value: %Trait.Value{value: true, type: :boolean}
      },
      %Trait{
        trait_key: "test_false",
        trait_value: %Trait.Value{value: Decimal.new(1), type: :decimal}
      }
    ]

    refute Flagsmith.Engine.traits_match_segment_rule(traits_3, @segment_rule_nested_any, 1, 1)
  end

  @segment_rule_all_is_or_not_set %Segment.Rule{
    conditions: [],
    rules: [
      %Segment.Rule{
        conditions: [
          %Segment.Condition{
            operator: :IS_SET,
            property_: "test_is_set"
          },
          %Segment.Condition{
            operator: :IS_NOT_SET,
            property_: "test_is_not_set"
          }
        ],
        rules: [],
        type: :ALL
      }
    ],
    type: :ALL
  }

  test "Segment.Rule IS_SET and IS_NOT_SET" do
    # test_false is in the inner rule condition, there's two inner conditions for the
    # it, both equals for false and true, so it should always test true with `ANY`
    traits_1 = [
      %Trait{
        trait_key: "test_is_set",
        trait_value: %Trait.Value{value: true, type: :boolean}
      }
    ]

    assert Flagsmith.Engine.traits_match_segment_rule(
             traits_1,
             @segment_rule_all_is_or_not_set,
             1,
             1
           )

    traits_2 = [
      %Trait{
        trait_key: "test_is_set",
        trait_value: %Trait.Value{value: true, type: :boolean}
      },
      %Trait{
        trait_key: "test_is_not_set",
        trait_value: %Trait.Value{value: true, type: :boolean}
      }
    ]

    refute Flagsmith.Engine.traits_match_segment_rule(
             traits_2,
             @segment_rule_all_is_or_not_set,
             1,
             1
           )
  end
end
