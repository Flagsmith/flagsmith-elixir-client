defmodule Flagsmith.Bench.InstrumentHooks do
  @moduledoc """
  Bindings to CodSpeed's instrument-hooks library, loaded from the NIF at `INSTRUMENT_HOOKS_NIF`.
  """
  @on_load :load_nif

  def load_nif do
    "INSTRUMENT_HOOKS_NIF"
    |> System.fetch_env!()
    |> String.to_charlist()
    |> :erlang.load_nif(0)
  end

  def is_instrumented, do: :erlang.nif_error(:not_loaded)
  def set_integration(_name, _version), do: :erlang.nif_error(:not_loaded)
  def start_benchmark, do: :erlang.nif_error(:not_loaded)
  def stop_benchmark, do: :erlang.nif_error(:not_loaded)
  def set_executed_benchmark(_uri), do: :erlang.nif_error(:not_loaded)
  def add_benchmark_timestamps(_start, _end), do: :erlang.nif_error(:not_loaded)
  def current_timestamp, do: :erlang.nif_error(:not_loaded)
end

defmodule Flagsmith.Bench.CodSpeed do
  @moduledoc """
  Measures benchmarks for CodSpeed's walltime instrument, following pytest-codspeed's
  warmup and round sizing, and reports them as CodSpeed walltime results.
  """
  alias Flagsmith.Bench.InstrumentHooks

  @integration_name "flagsmith-elixir-client-benchmarks"
  @integration_version "0.1.0"
  @warmup_time_ns 1_000_000_000
  @max_time_ns 3_000_000_000
  @min_round_time_ns 1_000_000

  @doc """
  Register this harness with the CodSpeed runner.
  """
  def init do
    IO.puts("CodSpeed instrumentation: #{InstrumentHooks.is_instrumented()}")
    :ok = InstrumentHooks.set_integration(@integration_name, @integration_version)
  end

  @doc """
  Measure a function, returning its walltime benchmark result.
  """
  def bench(name, uri, function) do
    __codspeed_root_frame__(function)

    {warmup_times_ns, warmup_iters} = warmup(function)
    warmup_mean_ns = Enum.sum(warmup_times_ns) / warmup_iters

    iter_per_round =
      if warmup_mean_ns <= @min_round_time_ns,
        do: ceil(@min_round_time_ns / warmup_mean_ns),
        else: 1

    rounds = max(1, trunc(@max_time_ns / (warmup_mean_ns * iter_per_round)))

    :ok = InstrumentHooks.start_benchmark()
    run_start = :erlang.monotonic_time(:nanosecond)
    times_per_round_ns = run_rounds(function, iter_per_round, rounds, run_start, [])
    :ok = InstrumentHooks.stop_benchmark()
    :ok = InstrumentHooks.set_executed_benchmark(uri)

    %{
      name: name,
      uri: uri,
      config: %{
        warmup_time_ns: @warmup_time_ns,
        min_round_time_ns: @min_round_time_ns,
        max_time_ns: @max_time_ns,
        max_rounds: nil
      },
      stats: stats(times_per_round_ns, iter_per_round, warmup_iters)
    }
  end

  @doc """
  Write walltime results where the CodSpeed runner collects them.
  """
  def write_results(benchmarks) do
    case System.get_env("CODSPEED_PROFILE_FOLDER") do
      nil ->
        :ok

      profile_folder ->
        pid = System.pid()
        results_dir = Path.join(profile_folder, "results")
        File.mkdir_p!(results_dir)

        results = %{
          creator: %{
            name: @integration_name,
            version: @integration_version,
            pid: String.to_integer(pid)
          },
          instrument: %{type: "walltime"},
          benchmarks: benchmarks
        }

        File.write!(Path.join(results_dir, "#{pid}.json"), Jason.encode_to_iodata!(results))
    end
  end

  def __codspeed_root_frame__(function), do: function.()

  defp warmup(function) do
    warmup_start = :erlang.monotonic_time(:nanosecond)
    warmup(function, warmup_start, [], 0)
  end

  defp warmup(function, warmup_start, times_ns, iters) do
    start = :erlang.monotonic_time(:nanosecond)
    __codspeed_root_frame__(function)
    finish = :erlang.monotonic_time(:nanosecond)
    times_ns = [finish - start | times_ns]

    if finish - warmup_start > @warmup_time_ns,
      do: {times_ns, iters + 1},
      else: warmup(function, warmup_start, times_ns, iters + 1)
  end

  defp run_rounds(_function, _iter_per_round, 0, _run_start, times_ns),
    do: Enum.reverse(times_ns)

  defp run_rounds(function, iter_per_round, rounds_left, run_start, times_ns) do
    hooks_start = InstrumentHooks.current_timestamp()
    start = :erlang.monotonic_time(:nanosecond)
    run_iterations(function, iter_per_round)
    finish = :erlang.monotonic_time(:nanosecond)

    :ok =
      InstrumentHooks.add_benchmark_timestamps(hooks_start, InstrumentHooks.current_timestamp())

    times_ns = [finish - start | times_ns]

    if finish - run_start > @max_time_ns,
      do: Enum.reverse(times_ns),
      else: run_rounds(function, iter_per_round, rounds_left - 1, run_start, times_ns)
  end

  defp run_iterations(_function, 0), do: :ok

  defp run_iterations(function, iterations) do
    __codspeed_root_frame__(function)
    run_iterations(function, iterations - 1)
  end

  # Mirrors `WalltimeBenchmark::from_runtime_data` in CodSpeed's runner-shared crate.
  defp stats(times_per_round_ns, iter_per_round, warmup_iters) do
    sorted = times_per_round_ns |> Enum.map(&(div(&1, iter_per_round) * 1.0)) |> Enum.sort()
    rounds = length(sorted)
    mean_ns = Enum.sum(sorted) / rounds
    q1_ns = quantile(sorted, 0.25)
    q3_ns = quantile(sorted, 0.75)
    stdev_ns = sample_stdev(sorted, mean_ns)
    iqr = q3_ns - q1_ns

    %{
      min_ns: List.first(sorted),
      max_ns: List.last(sorted),
      mean_ns: mean_ns,
      stdev_ns: stdev_ns,
      q1_ns: q1_ns,
      median_ns: median(sorted),
      q3_ns: q3_ns,
      rounds: rounds,
      total_time: Enum.sum(times_per_round_ns) / 1_000_000_000,
      iqr_outlier_rounds: Enum.count(sorted, &(&1 < q1_ns - 1.5 * iqr or &1 > q3_ns + 1.5 * iqr)),
      stdev_outlier_rounds: Enum.count(sorted, &(abs(&1 - mean_ns) > 2 * stdev_ns)),
      iter_per_round: iter_per_round,
      warmup_iters: warmup_iters
    }
  end

  defp median(sorted) do
    middle = div(length(sorted), 2)

    if rem(length(sorted), 2) == 0,
      do: (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2,
      else: Enum.at(sorted, middle)
  end

  defp quantile([only], _p), do: only
  defp quantile([first, second], p), do: first * (1 - p) + second * p

  defp quantile(sorted, p) do
    n = length(sorted)
    position = p * (n + 1) - 1
    index = floor(position)
    fraction = position - index

    if index + 1 < n,
      do: Enum.at(sorted, index) * (1 - fraction) + Enum.at(sorted, index + 1) * fraction,
      else: Enum.at(sorted, min(index, n - 1))
  end

  defp sample_stdev([_], _mean), do: 0.0

  defp sample_stdev(data, mean) do
    variance = Enum.sum(Enum.map(data, &((&1 - mean) ** 2))) / (length(data) - 1)
    :math.sqrt(variance)
  end
end
