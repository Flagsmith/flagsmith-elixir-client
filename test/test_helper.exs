Mox.defmock(FlagsmithEngine.MockHashing, for: FlagsmithEngine.HashingBehaviour)
Application.put_env(FlagsmithEngine, :hash_module, FlagsmithEngine.MockHashing)

## Id keeper - agent so we can just use this to retrieve new ids
FlagsmithEngine.Test.IDKeeper.start_link()

ExUnit.start()
