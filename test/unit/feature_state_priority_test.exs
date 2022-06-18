defmodule Flagsmith.Engine.FeatureState.Priority.Test do
  use ExUnit.Case, async: true

  alias Flagsmith.Schemas.Environment.FeatureState

  test "FeatureStates with nil FeatureSegments have no priority" do
    fs_1 = %FeatureState{}
    fs_2 = %FeatureState{}

    refute FeatureState.is_higher_priority?(fs_1, fs_2)
    refute FeatureState.is_higher_priority?(fs_2, fs_1)
  end

  test "FeatureState with a FeatureSegment priority is always higher priority than one without" do
    # priority defaults to 0 if not specified when the struct is initialized
    fs_1 = %FeatureState{feature_segment: %FeatureState.FeatureSegment{}}
    fs_2 = %FeatureState{}

    assert FeatureState.is_higher_priority?(fs_1, fs_2)
    refute FeatureState.is_higher_priority?(fs_2, fs_1)
  end

  test "FeatureState with the lowest number as priority is always higher priority" do
    fs_0 = %FeatureState{feature_segment: %FeatureState.FeatureSegment{priority: 0}}
    fs_1 = %FeatureState{feature_segment: %FeatureState.FeatureSegment{priority: 1}}
    fs_2 = %FeatureState{feature_segment: %FeatureState.FeatureSegment{priority: 2}}

    assert FeatureState.is_higher_priority?(fs_0, fs_1)
    assert FeatureState.is_higher_priority?(fs_0, fs_2)

    refute FeatureState.is_higher_priority?(fs_1, fs_0)
    assert FeatureState.is_higher_priority?(fs_1, fs_2)

    refute FeatureState.is_higher_priority?(fs_0, fs_0)
    refute FeatureState.is_higher_priority?(fs_2, fs_1)
  end
end
