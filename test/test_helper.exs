Mox.defmock(Flagsmith.Engine.MockHashing, for: Flagsmith.Engine.HashingBehaviour)
Application.put_env(:flagsmith_engine, :hash_module, Flagsmith.Engine.MockHashing)

Mox.defmock(Tesla.Adapter.Mock, for: Tesla.Adapter)
Application.put_env(:tesla, :adapter, {Tesla.Adapter.Mock, []})

## Id keeper - agent so we can just use this to retrieve new ids
Flagsmith.Engine.Test.IDKeeper.start_link()

ExUnit.start()
