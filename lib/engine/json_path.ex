defmodule Flagsmith.Engine.JSONPath do
  @moduledoc false

  # RFC 9535 subset: name, wildcard and index selectors, one per segment

  @type segment :: {:name, String.t()} | {:index, integer()} | :wildcard

  @blank [?\s, ?\t, ?\n, ?\r]

  @doc """
  Compile a JSONPath query into a list of segments. Returns `:error` for
  queries that are invalid, or use syntax outside the supported subset.
  """
  @spec compile(String.t()) :: {:ok, list(segment())} | :error
  def compile("$" <> rest), do: segments(rest, [])
  def compile(_), do: :error

  @doc """
  Find the first node selected by a compiled query in `data`.
  """
  @spec find_one(term(), list(segment())) :: {:ok, term()} | :error
  def find_one(data, []), do: {:ok, data}

  def find_one(data, [segment | rest]) do
    data
    |> select(segment)
    |> Enum.find_value(:error, fn node ->
      case find_one(node, rest) do
        {:ok, _} = found -> found
        :error -> nil
      end
    end)
  end

  @doc """
  The nodes a single segment selects from `data`.
  """
  @spec select(term(), segment()) :: list(term())
  def select(data, {:name, name}) when is_map(data) do
    case Map.fetch(data, name) do
      {:ok, value} -> [value]
      :error -> []
    end
  end

  def select(data, {:index, index}) when is_list(data) do
    case Enum.fetch(data, index) do
      {:ok, value} -> [value]
      :error -> []
    end
  end

  def select(data, :wildcard) when is_map(data), do: Map.values(data)
  def select(data, :wildcard) when is_list(data), do: data
  def select(_, _), do: []

  defp segments("", acc), do: {:ok, Enum.reverse(acc)}
  defp segments(<<c, rest::binary>>, acc) when c in @blank, do: segments(rest, acc)
  defp segments(".*" <> rest, acc), do: segments(rest, [:wildcard | acc])
  defp segments(".." <> _, _), do: :error

  defp segments("." <> rest, acc) do
    case member_name(rest) do
      {"", _} -> :error
      {name, rest} -> segments(rest, [{:name, name} | acc])
    end
  end

  defp segments("[" <> rest, acc) do
    with {:ok, selector, rest} <- selector(skip_blank(rest)),
         "]" <> rest <- skip_blank(rest) do
      segments(rest, [selector | acc])
    else
      _ -> :error
    end
  end

  defp segments(_, _), do: :error

  defp member_name(string), do: member_name(string, "")

  defp member_name(<<c::utf8, rest::binary>>, name)
       when c in ?a..?z or c in ?A..?Z or c == ?_ or c in 0x80..0xD7FF or
              c in 0xE000..0x10FFFF or (c in ?0..?9 and name != ""),
       do: member_name(rest, name <> <<c::utf8>>)

  defp member_name(rest, name), do: {name, rest}

  defp selector("*" <> rest), do: {:ok, :wildcard, rest}

  defp selector(<<delimiter, rest::binary>>) when delimiter in [?', ?"],
    do: string(rest, delimiter, "")

  defp selector(string) do
    case Integer.parse(string) do
      {index, rest} -> {:ok, {:index, index}, rest}
      :error -> :error
    end
  end

  defp string(<<delimiter, rest::binary>>, delimiter, acc), do: {:ok, {:name, acc}, rest}
  defp string("\\b" <> rest, delimiter, acc), do: string(rest, delimiter, acc <> "\b")
  defp string("\\f" <> rest, delimiter, acc), do: string(rest, delimiter, acc <> "\f")
  defp string("\\n" <> rest, delimiter, acc), do: string(rest, delimiter, acc <> "\n")
  defp string("\\r" <> rest, delimiter, acc), do: string(rest, delimiter, acc <> "\r")
  defp string("\\t" <> rest, delimiter, acc), do: string(rest, delimiter, acc <> "\t")
  defp string("\\/" <> rest, delimiter, acc), do: string(rest, delimiter, acc <> "/")
  defp string("\\\\" <> rest, delimiter, acc), do: string(rest, delimiter, acc <> "\\")

  defp string(<<?\\, delimiter, rest::binary>>, delimiter, acc),
    do: string(rest, delimiter, acc <> <<delimiter>>)

  defp string(<<"\\u", hex::binary-size(4), rest::binary>>, delimiter, acc) do
    case Integer.parse(hex, 16) do
      {codepoint, ""} when codepoint not in 0xD800..0xDFFF ->
        string(rest, delimiter, acc <> <<codepoint::utf8>>)

      _ ->
        :error
    end
  end

  defp string("\\" <> _, _, _), do: :error

  defp string(<<c::utf8, rest::binary>>, delimiter, acc),
    do: string(rest, delimiter, acc <> <<c::utf8>>)

  defp string(_, _, _), do: :error

  defp skip_blank(<<c, rest::binary>>) when c in @blank, do: skip_blank(rest)
  defp skip_blank(string), do: string
end
