defmodule Flagsmith.Client.PollerErrors.Test do
  use ExUnit.Case, async: false

  import Mox
  import Flagsmith.Test.Helpers, only: [assert_request: 2]

  alias Flagsmith.Engine.Test
  alias Flagsmith.Schemas

  @environment_header Flagsmith.Configuration.environment_header()
  @api_url Flagsmith.Configuration.default_url()
  @api_paths Flagsmith.Configuration.api_paths()

  # usually we want to ensure through careful allowances that a given process is
  # the one calling the mocks, but in this case it makes it much more difficult to
  # follow through because it's a process started through a dynamic supervisor
  # that then spawns requests that they themselves are the ones calling the mocks
  # so we set it to global and we'll use stubs and do our own logic in the stub
  # resolution.
  # Stubs aren't verified but because we have the right assertions - initialization
  # error that we get an exit, and the refresh that we get all corresponding messages
  # plus that the final state of the flags is as expected we can be confident that
  # those 2 situations are tested and properly converge on the expected output
  setup :set_mox_global

  # we start the supervisor as a supervised process so it's shut down on every test
  # and subsequently shutting down the individual dynamic supervisor for the poller(s)
  # which in turn will make the poller shutdown too
  setup do
    start_supervised!(Flagsmith.Supervisor)
    :ok
  end

  setup do
    config =
      Flagsmith.Client.new(
        enable_local_evaluation: true,
        environment_key: "test_key"
      )

    [config: config]
  end

  test "initializing with api error", %{config: config} do
    stub(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
      assert_request(
        tesla_env,
        body: nil,
        query: [],
        headers: [{@environment_header, "test_key"}],
        url: Path.join([@api_url, @api_paths.environment]) <> "/",
        method: :get
      )

      {:error, :noop}
    end)

    # here we start it through the dynamic supervisor instead of directly
    # since we don't want the process exit to exit the test as well
    {:ok, _pid} = Flagsmith.Client.Poller.Supervisor.start_child(config)

    # we assert that we'll have an exit from the function since the call will fail
    assert catch_exit(Flagsmith.Client.get_environment(config))
  end

  test "refresh with errors retries in next cycle", %{config: config} do
    config = %{config | environment_refresh_interval_milliseconds: 3}
    env_response = Jason.decode!(Test.Generators.json_env())

    test_process = self()
    # we use a counter to keep track of how many times the stub has been called
    # first (0) is normal response
    # second (1) is the refresh error
    # third and last (2) is the refresh ok with updated features states being an empty
    # list
    ref_counter = :counters.new(1, [:atomics])

    # stub the call for first call
    stub(Tesla.Adapter.Mock, :call, fn tesla_env, _options ->
      assert_request(
        tesla_env,
        body: nil,
        query: [],
        headers: [{@environment_header, "test_key"}],
        url: Path.join([@api_url, @api_paths.environment]) <> "/",
        method: :get
      )

      case :counters.get(ref_counter, 1) do
        0 ->
          :counters.add(ref_counter, 1, 1)
          send(test_process, :ok)
          {:ok, %Tesla.Env{status: 200, body: env_response}}

        1 ->
          :counters.add(ref_counter, 1, 1)
          send(test_process, :ok)
          {:error, :noop}

        2 ->
          poller_pid = Flagsmith.Client.Poller.whereis("test_key")
          :ok = :gen_statem.call(poller_pid, {:update_refresh_rate, 60_000})
          new_env_response = %{env_response | "feature_states" => []}
          send(test_process, :ok)
          {:ok, %Tesla.Env{status: 200, body: new_env_response}}
      end
    end)

    {:ok, _pid} = Flagsmith.Client.Poller.Supervisor.start_child(config)

    # we ensure that it has been called all 3 times by receiving 3 :ok messages that
    # are sent from the stub resolution
    Enum.each(1..3, fn n ->
      receive do
        :ok -> :ok
      after
        500 ->
          raise "didn't receive stub call number #{n}"
      end
    end)

    # because we waited for 3 :ok messages we know the stub has to have been resolved
    # 3 times and as such the state of the poller should hold the last feature states
    # which to disambiguate from the normal mock response is in this case an empty list
    # and so if we have 0 flags it must mean that the poller held the last valid call
    # and also that it refreshed after the error
    assert Flagsmith.Test.Helpers.wait_until(
             fn ->
               {:ok, %Schemas.Flags{flags: flags}} =
                 Flagsmith.Client.get_environment_flags(config)

               flags == %{}
             end,
             200
           )
  end
end
