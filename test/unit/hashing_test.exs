defmodule FlagsmithEngine.HashingTest do
  use ExUnit.Case, async: true

  # this will generate random ids whenever called so the more assertions use it
  # the more it verifies those assertions are correct if they pass. If for some
  # reason a test using it fails, it must be either a bug on the implementation
  # or a logical error on the test/assumptions
  def generate_random_ids(n_a \\ 2, n_b \\ 5) do
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

      [row | acc]
    end)
  end

  test "percentage between 0 and 100" do
    ids = generate_random_ids()

    percentage = FlagsmithEngine.percentage_from_ids(ids)

    assert 100 > percentage and percentage >= 0
  end

  test "percentage is the same when run multiple times with the same ids" do
    ids = generate_random_ids()
    assert FlagsmithEngine.percentage_from_ids(ids) == FlagsmithEngine.percentage_from_ids(ids)
  end

  test "percentage is different between different ids" do
    ids_1 = [10, 5200]
    ids_2 = [5200, 10]

    assert FlagsmithEngine.percentage_from_ids(ids_1) !=
             FlagsmithEngine.percentage_from_ids(ids_2)
  end

  test "ids are evenly distributed" do
    sample = 500
    buckets = 50
    bucket_size = round(sample / buckets)
    error = 0.1

    ids = for a <- 1..500, b <- 1..500, do: [a, b]

    values =
      ids
      |> Enum.map(&FlagsmithEngine.percentage_from_ids(&1))
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
end
