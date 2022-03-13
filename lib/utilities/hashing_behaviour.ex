defmodule Flagsmith.Engine.HashingBehaviour do
  @moduledoc false
  @callback hash(String.t()) :: binary()

  def hash(stringed), do: impl().hash(stringed)

  defp impl(),
    do: Application.get_env(:flagsmith_engine, :hash_module, Flagsmith.Engine.HashingUtils)
end
