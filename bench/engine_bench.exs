# Benchmarks identity evaluation through the public engine API, so the same
# script runs against older versions of the SDK for comparison.
#
#   mix run bench/engine_bench.exs [seconds per workload] [workload names...]

alias Flagsmith.Engine
alias Flagsmith.Schemas.Identity

defmodule Flagsmith.Bench.Environments do
  @moduledoc false

  @features 100
  @segments 50
  @identities 100
  @chain 10

  def v1_suite do
    json = "test/data/environment_n9fbf9h3v4fFgH3U3ngWhb.json" |> File.read!() |> Jason.decode!()
    {:ok, env} = Engine.parse_environment(json["environment"])

    identities =
      for %{"identity" => identity} <- json["identities_and_responses"] do
        identity["identifier"]
        |> Identity.from_id_traits(identity["identity_traits"])
        |> Map.put(:django_id, identity["django_id"])
      end

    {env, identities}
  end

  def synthetic(dependent? \\ false) do
    {:ok, env} =
      Engine.parse_environment(%{
        "api_key" => "bench-key",
        "name" => "Bench",
        "feature_states" => Enum.map(1..@features, &feature_state(&1, nil)),
        "project" => %{
          "hide_disabled_flags" => false,
          "segments" => Enum.map(1..@segments, &segment(&1, dependent?))
        }
      })

    identities =
      for n <- 1..@identities do
        traits = [
          %{"trait_key" => "plan", "trait_value" => "plan_#{rem(n, 5)}"},
          %{"trait_key" => "age", "trait_value" => rem(n, 60)},
          %{"trait_key" => "country", "trait_value" => Enum.at(~w(gb us fr de), rem(n, 4))},
          %{"trait_key" => "version", "trait_value" => "1.#{rem(n, 10)}.0"},
          %{"trait_key" => "beta", "trait_value" => rem(n, 2) == 0}
        ]

        identity = Identity.from_id_traits("user_#{n}", traits)

        case rem(n, 10) do
          0 ->
            {:ok, overridden} =
              Identity.changeset(identity, %{
                "identity_features" =>
                  for i <- [1, 2, 3] do
                    %{
                      "enabled" => true,
                      "feature" => feature(i),
                      "feature_state_value" => "identity_#{n}"
                    }
                  end
              })
              |> Ecto.Changeset.apply_action(:insert)

            overridden

          _ ->
            identity
        end
      end

    {env, identities}
  end

  defp feature(i) do
    type = if rem(i, 10) == 0, do: "MULTIVARIATE", else: "STANDARD"
    %{"id" => i, "name" => "feature_#{i}", "type" => type}
  end

  defp feature_state(i, priority) do
    django_id = if priority, do: 10_000 * priority + i, else: i

    state = %{
      "django_id" => django_id,
      "featurestate_uuid" =>
        "00000000-0000-0000-0000-#{String.pad_leading("#{django_id}", 12, "0")}",
      "enabled" => rem(i, 3) != 0,
      "feature" => feature(i),
      "feature_state_value" => "value_#{i}",
      "multivariate_feature_state_values" =>
        case rem(i, 10) do
          0 ->
            for v <- 1..3 do
              %{
                "id" => 100 * i + v,
                "percentage_allocation" => 30,
                "multivariate_feature_option" => %{"id" => 100 * i + v, "value" => "variant_#{v}"}
              }
            end

          _ ->
            []
        end
    }

    case priority do
      nil -> state
      _ -> Map.put(state, "feature_segment", %{"priority" => priority})
    end
  end

  defp segment(j, dependent?) do
    conditions =
      [
        [
          condition("plan", "EQUAL", "plan_#{rem(j, 5)}"),
          condition("country", "IN", "gb,us")
        ],
        [
          condition("age", "GREATER_THAN", "#{rem(j, 40)}"),
          condition("version", "GREATER_THAN_INCLUSIVE", "1.#{rem(j, 8)}.0:semver")
        ],
        [condition("", "PERCENTAGE_SPLIT", "50"), condition("beta", "EQUAL", "true")]
      ]

    # segments overriding features 1..@chain each depend on the next feature
    conditions =
      case dependent? and j <= @chain do
        true ->
          conditions ++ [[condition("$.flags.feature_#{j + 1}.enabled", "EQUAL", "true")]]

        false ->
          conditions
      end

    %{
      "id" => j,
      "name" => "segment_#{j}",
      "rules" => [
        %{
          "type" => "ALL",
          "conditions" => [],
          "rules" => Enum.map(conditions, &%{"type" => "ANY", "conditions" => &1, "rules" => []})
        }
      ],
      "feature_states" => [feature_state(j, j), feature_state(j + @segments, j)]
    }
  end

  defp condition(property, operator, value),
    do: %{"property_" => property, "operator" => operator, "value" => value}
end

defmodule Flagsmith.Bench do
  @moduledoc false

  def run(name, seconds, fun) do
    run_for(fun, div(seconds * 1000, 4))
    {:reductions, reductions_before} = Process.info(self(), :reductions)
    fun.()
    {:reductions, reductions_after} = Process.info(self(), :reductions)

    times = run_for(fun, seconds * 1000) |> Enum.sort()
    count = length(times)
    mean = Enum.sum(times) / count

    IO.puts(
      Enum.join(
        [
          "",
          name,
          count,
          us(Enum.at(times, div(count, 2))),
          us(mean),
          us(Enum.at(times, min(count - 1, round(count * 0.99)))),
          reductions_after - reductions_before,
          ""
        ],
        " | "
      )
      |> String.trim()
    )
  end

  defp run_for(fun, ms) do
    deadline = System.monotonic_time(:millisecond) + ms
    loop(fun, deadline, [])
  end

  defp loop(fun, deadline, acc) do
    case System.monotonic_time(:millisecond) >= deadline do
      true ->
        acc

      false ->
        start = System.monotonic_time(:nanosecond)
        fun.()
        loop(fun, deadline, [System.monotonic_time(:nanosecond) - start | acc])
    end
  end

  defp us(ns), do: :erlang.float_to_binary(ns / 1000, decimals: 1)
end

{seconds, only} =
  case System.argv() do
    [seconds | only] -> {String.to_integer(seconds), only}
    [] -> {5, []}
  end

{v1_env, v1_identities} = Flagsmith.Bench.Environments.v1_suite()
{synthetic_env, synthetic_identities} = Flagsmith.Bench.Environments.synthetic()
{dependent_env, dependent_identities} = Flagsmith.Bench.Environments.synthetic(true)

# what newer versions keep of the last environment evaluated in a process
clear_cache = fn -> Process.delete({Flagsmith.Engine, :prepared_environment}) end

copies =
  Enum.map(synthetic_identities, fn _ ->
    :erlang.binary_to_term(:erlang.term_to_binary(synthetic_env))
  end)

workloads = [
  {"v1_suite_feature_states",
   fn -> Enum.each(v1_identities, &Engine.get_identity_feature_states(v1_env, &1)) end},
  {"v1_suite_feature_states_cold",
   fn ->
     Enum.each(v1_identities, fn identity ->
       clear_cache.()
       Engine.get_identity_feature_states(v1_env, identity)
     end)
   end},
  {"v1_suite_segments",
   fn -> Enum.each(v1_identities, &Engine.get_identity_segments(v1_env, &1)) end},
  {"synthetic_feature_states",
   fn ->
     Enum.each(synthetic_identities, &Engine.get_identity_feature_states(synthetic_env, &1))
   end},
  {"synthetic_feature_states_cold",
   fn ->
     Enum.each(synthetic_identities, fn identity ->
       clear_cache.()
       Engine.get_identity_feature_states(synthetic_env, identity)
     end)
   end},
  {"synthetic_feature_states_copied_env",
   fn ->
     synthetic_identities
     |> Enum.zip(copies)
     |> Enum.each(fn {identity, env} -> Engine.get_identity_feature_states(env, identity) end)
   end},
  {"synthetic_segments",
   fn -> Enum.each(synthetic_identities, &Engine.get_identity_segments(synthetic_env, &1)) end},
  {"dependent_feature_states",
   fn ->
     Enum.each(dependent_identities, &Engine.get_identity_feature_states(dependent_env, &1))
   end}
]

IO.puts("Elixir #{System.version()}, OTP #{System.otp_release()}, #{seconds}s per workload")
IO.puts("Times are per batch of identities (v1: 101, synthetic: 100), in microseconds.\n")
IO.puts("| workload | batches | median | mean | p99 | reductions/batch |")
IO.puts("| --- | --- | --- | --- | --- | --- |")

for {name, fun} <- workloads, only == [] or name in only do
  Flagsmith.Bench.run(name, seconds, fun)
end
