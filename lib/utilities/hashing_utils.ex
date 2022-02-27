defmodule Flagsmith.Engine.HashingUtils do
  @behaviour Flagsmith.Engine.HashingBehaviour

  def hash(stringed),
    do: :crypto.hash(:md5, stringed) |> Base.encode16()
end
