Code.require_file("codspeed.exs", __DIR__)

defmodule Flagsmith.SdkBenchmark.EnvironmentDocumentAdapter do
  @moduledoc """
  Serves an environment document from memory to any request.
  """
  @behaviour Tesla.Adapter

  @impl Tesla.Adapter
  def call(env, environment_document: environment_document) do
    {:ok,
     %{
       env
       | status: 200,
         headers: [{"content-type", "application/json"}],
         body: environment_document
     }}
  end
end

defmodule Flagsmith.SdkBenchmark do
  @moduledoc """
  Benchmarks a locally evaluating SDK client against environment documents tiered by size.
  """

  @file_uri Path.relative_to(__ENV__.file, Path.expand("..", __DIR__))
  @identity_overrides_identifier "identity-override-1"
  @identifier "user-1"
  @traits [
    %{trait_key: "plan", trait_value: "plan-7"},
    %{trait_key: "age", trait_value: 30},
    %{trait_key: "country", trait_value: "GB"},
    %{trait_key: "version", trait_value: "2.5.1"},
    %{trait_key: "email", trait_value: "jane@example.com"},
    %{trait_key: "user_id", trait_value: 12},
    %{trait_key: "beta", trait_value: true},
    %{trait_key: "score", trait_value: 95},
    %{trait_key: "tier", trait_value: "pro"},
    %{trait_key: "device", trait_value: "iPhone 15"}
  ]

  @benchmarks [
    :get_environment_flags,
    :get_identity_flags_with_identity_overrides,
    :get_identity_flags_no_traits,
    :get_identity_flags_with_traits
  ]
  @environments ["small", "medium", "large"]

  @doc """
  Run every benchmark against every environment, returning whether all of them succeeded.
  """
  def run do
    Flagsmith.Bench.CodSpeed.init()

    outcomes =
      for environment <- @environments,
          outcome <- run_environment(environment),
          do: outcome

    outcomes
    |> Enum.flat_map(fn
      {:ok, benchmark} -> [benchmark]
      {:error, _name} -> []
    end)
    |> Flagsmith.Bench.CodSpeed.write_results()

    Enum.all?(outcomes, &match?({:ok, _}, &1))
  end

  defp run_environment(environment) do
    client = build_client(environment)

    try do
      Enum.map(@benchmarks, &run_benchmark(&1, environment, client))
    after
      close_client()
    end
  end

  defp run_benchmark(benchmark, environment, client) do
    name = "#{benchmark}[#{environment}]"

    try do
      result =
        Flagsmith.Bench.CodSpeed.bench(name, "#{@file_uri}::#{name}", fn ->
          apply(__MODULE__, benchmark, [client])
        end)

      %{stats: %{mean_ns: mean_ns, rounds: rounds, iter_per_round: iter_per_round}} = result

      IO.puts(
        "#{name}: #{Float.round(mean_ns / 1000, 2)}µs (#{rounds} rounds × #{iter_per_round})"
      )

      {:ok, result}
    catch
      kind, reason ->
        IO.puts(:stderr, "#{name}: failed\n" <> Exception.format(kind, reason, __STACKTRACE__))
        {:error, name}
    end
  end

  @doc """
  Build a locally evaluating client serving the environment document from memory.
  """
  def build_client(environment) do
    environments_dir = System.fetch_env!("SDK_BENCHMARKS_ENVIRONMENTS_DIR")
    environment_document = File.read!(Path.join(environments_dir, "#{environment}.json"))

    Application.put_env(
      :tesla,
      :adapter,
      {Flagsmith.SdkBenchmark.EnvironmentDocumentAdapter,
       environment_document: environment_document}
    )

    {:ok, _} = Flagsmith.Supervisor.start_link()

    client =
      Flagsmith.Client.new(
        environment_key: "ser.benchmark",
        api_url: "http://flagsmith.benchmark/api/v1/",
        enable_local_evaluation: true,
        environment_refresh_interval_milliseconds: 86_400_000
      )

    {:ok, _} = Flagsmith.Client.get_environment(client)
    client
  end

  def close_client, do: Supervisor.stop(Flagsmith.Supervisor)

  @doc """
  Get a feature value from the environment flags.
  """
  def get_environment_flags(client) do
    {:ok, flags} = Flagsmith.Client.get_environment_flags(client)
    Flagsmith.Client.get_feature_value(flags, "feature_1")
  end

  @doc """
  Check a feature for an identity with identity overrides.
  """
  def get_identity_flags_with_identity_overrides(client) do
    {:ok, flags} =
      Flagsmith.Client.get_identity_flags(client, @identity_overrides_identifier, [])

    Flagsmith.Client.is_feature_enabled(flags, "feature_8")
  end

  @doc """
  Get a feature value for an identity without traits.
  """
  def get_identity_flags_no_traits(client) do
    {:ok, flags} = Flagsmith.Client.get_identity_flags(client, @identifier, [])
    Flagsmith.Client.get_feature_value(flags, "feature_1")
  end

  @doc """
  Get a feature value for an identity with traits.
  """
  def get_identity_flags_with_traits(client) do
    {:ok, flags} = Flagsmith.Client.get_identity_flags(client, @identifier, @traits)
    Flagsmith.Client.get_feature_value(flags, "feature_1")
  end
end

Logger.configure(level: :warning)

unless Flagsmith.SdkBenchmark.run(), do: System.halt(1)
