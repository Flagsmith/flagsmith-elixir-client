Mox.defmock(Flagsmith.Engine.MockHashing, for: Flagsmith.Engine.HashingBehaviour)
Application.put_env(Flagsmith.Engine, :hash_module, Flagsmith.Engine.MockHashing)

## Id keeper - agent so we can just use this to retrieve new ids
Flagsmith.Engine.Test.IDKeeper.start_link()

ExUnit.start()
