defmodule Flagsmith.Engine.HashingBehaviour do
  @callback hash(String.t()) :: binary()

  def hash(stringed), do: impl().hash(stringed)

  defp impl(),
    do: Application.get_env(Flagsmith.Engine, :hash_module, Flagsmith.Engine.HashingUtils)
end
