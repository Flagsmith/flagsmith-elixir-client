defmodule Flagsmith.Engine.EngineTestData.Test do
  use ExUnit.Case, async: true

  import Mox, only: [stub_with: 2]

  alias Flagsmith.Engine.Evaluator

  @test_cases_path Path.join([File.cwd!(), "test/support/engine-test-data/test_cases"])
  @test_case_paths @test_cases_path |> Path.join("*.json*") |> Path.wildcard() |> Enum.sort()

  setup do
    stub_with(Flagsmith.Engine.MockHashing, Flagsmith.Engine.HashingUtils)
    :ok
  end

  test "engine test data submodule is checked out" do
    # Given / When
    test_case_paths = @test_case_paths

    # Then
    assert test_case_paths != [], "Run `git submodule update --init` to fetch test data"
  end

  for path <- @test_case_paths do
    @external_resource path

    test "#{Path.basename(path)}" do
      # Given
      %{"context" => context, "result" => expected} = load_test_case(unquote(path))

      # When
      result = Evaluator.get_evaluation_result(context)

      # Then
      assert result == expected
    end
  end

  defp load_test_case(path) do
    test_case =
      path
      |> File.read!()
      |> String.replace(~r/^\s*\/\/.*$/m, "")
      |> Jason.decode!(objects: :ordered_objects)

    context =
      test_case["context"]
      |> to_map()
      # declaration order decides override ties and segment result order
      |> put_entries("features", test_case["context"]["features"])
      |> put_entries("segments", test_case["context"]["segments"])

    %{"context" => context, "result" => to_map(test_case["result"])}
  end

  defp put_entries(context, _key, nil), do: context

  defp put_entries(context, key, %Jason.OrderedObject{values: values}),
    do: Map.put(context, key, Enum.map(values, fn {k, v} -> {k, to_map(v)} end))

  defp to_map(%Jason.OrderedObject{values: values}),
    do: Map.new(values, fn {key, value} -> {key, to_map(value)} end)

  defp to_map(list) when is_list(list), do: Enum.map(list, &to_map/1)
  defp to_map(value), do: value
end
