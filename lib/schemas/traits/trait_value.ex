defmodule Flagsmith.Schemas.Traits.Trait.Value do
  @behaviour Ecto.Type

  @impl Ecto.Type
  def type(), do: :map

  @type t() :: %{
          :value => String.t() | number() | boolean(),
          :type => :string | :number | :boolean
        }

  @impl Ecto.Type
  def load(data), do: cast(data)

  @impl Ecto.Type
  def cast(%{value: _, type: _} = data), do: {:ok, data}

  def cast(%{"value" => value, "type" => type}),
    do: {:ok, %{value: value, type: String.to_existing_atom(type)}}

  def cast(data) when is_number(data),
    do: {:ok, %{value: data, type: :number}}

  def cast(data) when data in ["false", "true"],
    do: {:ok, %{value: String.to_existing_atom(data), type: :boolean}}

  def cast(data) when is_binary(data),
    do: {:ok, %{value: data, type: :string}}

  def cast(_), do: :error

  @impl Ecto.Type
  def dump(%{value: _, type: _} = data), do: {:ok, data}
  def dump(%{"value" => _, "type" => type} = data), do: {:ok, data}

  def dump(data) when is_number(data),
    do: {:ok, %{value: data, type: :number}}

  def dump(data) when data in ["false", "true"],
    do: {:ok, %{value: String.to_existing_atom(data), type: :boolean}}

  def dump(data) when is_binary(data),
    do: {:ok, %{value: data, type: :string}}

  def dump(_), do: :error

  @impl Ecto.Type
  def embed_as(_), do: :dump

  @impl Ecto.Type
  def equal?(term_1, term_1), do: true
  def equal?(term_1, term_2), do: get_term(term_1) == get_term(term_2)

  defp get_term(data) do
    case cast(data) do
      {:ok, value} -> value
      :error -> {:error, data}
    end
  end
end
