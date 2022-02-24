defmodule FlagsmithEngine.HashingUtils do
  @behaviour FlagsmithEngine.HashingBehaviour

  def hash(stringed),
    do: :crypto.hash(:md5, stringed) |> Base.hex_encode32()
end
