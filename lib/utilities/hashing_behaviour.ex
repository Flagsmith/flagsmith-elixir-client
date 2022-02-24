defmodule FlagsmithEngine.HashingBehaviour do
  @callback hash(String.t()) :: binary()

  def hash(stringed), do: impl().hash(stringed)

  defp impl(),
    do: Application.get_env(FlagsmithEngine, :hash_module, FlagsmithEngine.HashingUtils)
end
