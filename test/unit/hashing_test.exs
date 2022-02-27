defmodule Flagsmith.Engine.HashingTest do
  use ExUnit.Case, async: false

  import Mox, only: [stub_with: 2, verify_on_exit!: 1, expect: 3]

  setup do
    stub_with(Flagsmith.Engine.MockHashing, Flagsmith.Engine.HashingUtils)
    :ok
  end

  # this will generate random ids whenever called so the more assertions use it
  # the more it verifies those assertions are correct if they pass. If for some
  # reason a test using it fails, it must be either a bug on the implementation
  # or a logical error on the test/assumptions
  def generate_random_ids(n_a \\ 5, n_b \\ 2) do
    Enum.reduce(1..n_a, [], fn _, acc ->
      row =
        Enum.reduce(1..n_b, [], fn _, acc_row ->
          new_val =
            case Enum.random([:int, :uuid]) do
              :int -> :rand.uniform(500_000)
              :uuid -> Ecto.UUID.generate()
            end

          [new_val | acc_row]
        end)
        |> Enum.reverse()

      [row | acc]
    end)
  end

  test "percentage between 0 and 100" do
    generate_random_ids()
    |> Enum.each(fn ids ->
      percentage = Flagsmith.Engine.percentage_from_ids(ids)
      assert 100 > percentage and percentage >= 0
    end)
  end

  test "percentage is the same when run multiple times with the same ids" do
    generate_random_ids()
    |> Enum.each(fn ids ->
      assert Flagsmith.Engine.percentage_from_ids(ids) ==
               Flagsmith.Engine.percentage_from_ids(ids)
    end)
  end

  test "percentage is different between different ids" do
    ids_1 = [10, 5200]
    ids_2 = [5200, 11]

    assert Flagsmith.Engine.percentage_from_ids(ids_1) !=
             Flagsmith.Engine.percentage_from_ids(ids_2)
  end

  test "ids are evenly distributed" do
    sample = 500
    buckets = 50
    bucket_size = round(sample / buckets)
    error = 0.1

    ids = for a <- 1..500, b <- 1..500, do: [a, b]

    values =
      ids
      |> Enum.map(&Flagsmith.Engine.percentage_from_ids(&1))
      |> Enum.sort()

    for i <- 1..buckets do
      bucket_start = i * bucket_size
      bucket_end = (i + 1) * bucket_size

      bucket_value_limit =
        Enum.min([
          (i + 1) / buckets + error * ((i + 1) / buckets),
          1
        ])

      assert values
             |> Enum.slice(bucket_start..bucket_end)
             |> Enum.all?(&(&1 <= bucket_value_limit))
    end
  end

  describe "with mock" do
    setup :verify_on_exit!

    # to understand this test read the comments on that test
    # https://github.com/Flagsmith/flagsmith-engine/blob/c34b4baeea06d31d221433053b64c1e855fd8d4d/tests/unit/utils/test_utils_hashing.py#L95
    # basically we mock the hashing so that the hex string returned from the hashing
    # provides given values. In this case, 100 and 0. Since when the percentage is 100
    # the function is expected to try again until it no longer is (by duplicating the
    # ids used to hash) it should follow that if the first call returns 100 the hashing
    # function should be called again, hence why we set up 2 expectations

    test "percentage_from_ids doesn't return 100 as percentage" do
      # the first time it's called it will return a string that parses to 100 so it
      # percentage_from_ids/1 should call again the hash util in order to get a new
      # try at hashing until it's no longer 100
      expect(Flagsmith.Engine.MockHashing, :hash, fn stringed ->
        assert stringed == "12,93"
        "270e"
      end)

      # this second time this string parses to 0
      expect(Flagsmith.Engine.MockHashing, :hash, fn stringed ->
        assert stringed == "12,93,12,93"
        "270f"
      end)

      object_ids = [12, 93]

      value = Flagsmith.Engine.percentage_from_ids(object_ids)

      # the value is 0 as defined by the second call to the mock
      assert value == 0
    end
  end
end
