defmodule FlagsmithEngine.PollerTest do
  use ExUnit.Case, async: false

  import FlagsmithEngine.Test.Helpers, only: [ensure_no_poller: 1]
  import Mox, only: [verify_on_exit!: 1, expect: 3, allow: 3]

  # setup Mox to verify any expectations 
  setup :verify_on_exit!

  # we make sure the poller is not running at the beginning of any test if it is
  # we shut it down so that it no longer is and can start fresh when needed
  setup :ensure_no_poller

  describe "starting up" do
    test "fails to start the poller without a key" do
      assert {:error, {:invalid_key, nil}} = FlagsmithEngine.Poller.start_link()
    catch
      :exit, {:error, {:invalid_key, nil}} ->
        assert true
    end

    test "starts the poller" do
      # Set an expectation that the tesla adapter will be called.
      # since after the initialization the poller should retrieve the flags to cache
      # them, we should have a call to the flagsmith api, with the Environment header
      # matching the api key we pass. Since `Tesla.Adapter` is a behaviour and we're
      # mocking it (test_helpers.exs) we can assert that the `call` function in it
      # is going to be "called", with the first argument the `Tesla.Env` struct
      # and the second any options passed to the adapter (which we don't care
      # in this case and will nonetheless be an empty kword list).

      expect(Tesla.Adapter.Mock, :call, fn %{url: url, headers: headers}, _options ->
        assert url == "https://api.flagsmith.com/api/v1/flags/"

        assert Enum.any?(headers, fn {header, value} ->
                 header == "X-Environment-Key" and value == "test"
               end)

        {:ok, %{status: 200, body: []}}
      end)

      # Start the poller
      assert {:ok, pid} = FlagsmithEngine.Poller.start_link(api_key: "test")
      # Since it's the poller doing the http request (and it's a different process
      # than the one running the test), we need to explictly say that that process
      # is allowed to trigger the expectations set by this (self()) process
      allow(Tesla.Adapter.Mock, self(), pid)

      # we need to make a synchronous interaction with the poller so that it has time
      # to execute the loading (in this case, http call) so that our mock is fired
      # as expected. This is needed because on init the poller only sets
      # some internal state and immediately replies. The "loading" is done next,
      # but always before any other thing, so when we do a synchronous call to it,
      # like in this case `:sys.get_state`, every internal action has to have occurred
      # prior to the statem replying to the synchronous call, so when it replies,
      # the mock expectation should have been triggered. Without this synch call,
      # the test would finish prior to the mock being fulfilled.
      # Since we have to do that, we take the chance and also assert that its state
      # is as how we would expect, though if the internals change that part might
      # also need to be changed
      assert {:loaded,
              %FlagsmithEngine.Poller{
                client: %Flagsmith.SDK.Client{
                  base_url: "https://api.flagsmith.com/api/v1/",
                  environment_key: "test"
                },
                ets: FlagsmithEngine.Poller,
                loaded: true
              }} = :sys.get_state(pid)
    end
  end
end
