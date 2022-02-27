defmodule Flagsmith.Engine.Test.IDKeeper do
  use Agent

  def start_link(),
    do: Agent.start_link(fn -> 1 end, name: __MODULE__)

  def current(),
    do: Agent.get(__MODULE__, & &1)

  def inc(),
    do: Agent.update(__MODULE__, &(&1 + 1))

  def get_and_update() do
    with value <- current(),
         :ok <- inc() do
      value
    end
  end
end
