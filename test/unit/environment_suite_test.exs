defmodule Flagsmith.Engine.EnvironmentSuite.Test do
  use ExUnit.Case, async: true

  import Mox, only: [stub_with: 2]

  alias Flagsmith.Schemas

  @path Path.join([
          File.cwd!(),
          "test/support/engine-test-data/data/environment_n9fbf9h3v4fFgH3U3ngWhb.json"
        ])

  @json_env @path |> File.read!() |> Jason.decode!()
  @parsed_env (case(Flagsmith.Engine.parse_environment(Map.get(@json_env, "environment"))) do
                 {:ok, parsed} -> parsed
                 error -> raise IO.inspect(error, limit: :infinity, printable_limit: :infinite)
               end)

  setup do
    stub_with(Flagsmith.Engine.MockHashing, Flagsmith.Engine.HashingUtils)
    [env: @parsed_env]
  end

  Map.get(@json_env, "identities_and_responses")
  |> Enum.each(fn %{
                    "identity" => %{
                      "identifier" => id,
                      "identity_traits" => traits,
                      "django_id" => django_id
                    },
                    "response" => %{"flags" => response_flags}
                  } ->
    test "#{id} from json spec", %{env: %{api_key: api_key} = env} do
      config = Flagsmith.Client.new(environment_key: api_key)

      identity =
        Flagsmith.Schemas.Identity.from_id_traits(unquote(id), unquote(Macro.escape(traits)))
        |> Map.put(:django_id, unquote(django_id))

      assert %Schemas.Flags{flags: flags} =
               env
               |> Flagsmith.Engine.get_identity_feature_states(identity)
               |> Flagsmith.Client.build_flags(config)

      Enum.each(unquote(Macro.escape(response_flags)), fn %{
                                                            "feature" => %{"name" => feature_name},
                                                            "feature_state_value" => fsv,
                                                            "enabled" => enabled
                                                          } ->
        assert %Schemas.Flag{enabled: ^enabled, value: ^fsv} = Map.get(flags, feature_name)
      end)

      assert Enum.count(flags) == Enum.count(unquote(Macro.escape(response_flags)))
    end
  end)
end
