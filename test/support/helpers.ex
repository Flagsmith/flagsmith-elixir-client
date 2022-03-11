defmodule Flagsmith.Test.Helpers do
  import ExUnit.Assertions, only: [assert: 1]

  def assert_request(env, to_assert),
    do: Enum.each(to_assert, fn {k, v} -> assert_request_key(k, v, env) end)

  defp assert_request_key(key, vals, env) when key in [:headers, :query],
    do: assert_multiple_kv(vals, Map.get(env, key, []))

  defp assert_request_key(key, val, env),
    do: assert(val == Map.get(env, key))

  defp assert_multiple_kv(to_assert, actual) do
    Enum.all?(to_assert, fn {header, val} ->
      assert Enum.any?(actual, fn {header_req, val_req} ->
               header == header_req && val == val_req
             end)
    end)
  end
end
