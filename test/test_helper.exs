## Mocks for tesla so we can mock the api calls
Mox.defmock(Tesla.Adapter.Mock, for: Tesla.Adapter)
Application.put_env(:tesla, :adapter, {Tesla.Adapter.Mock, []})

## Id keeper - agent so we can just use this to retrieve new ids
FlagsmithEngine.Test.IDKeeper.start_link()

ExUnit.start()
