defmodule FlagsmithEngine.Test.Helpers do
  def ensure_no_poller(_ctx) do
    case Process.whereis(FlagsmithEngine.Poller) do
      nil ->
        :ok

      pid ->
        Process.exit(pid, :shutdown)

        case Process.alive?(pid) do
          false -> :ok
          _ -> :is_alive
        end
    end
  end
end
