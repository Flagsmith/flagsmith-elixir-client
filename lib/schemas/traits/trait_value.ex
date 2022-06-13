defmodule Flagsmith.Schemas.Traits.Trait.Value do
  @behaviour Ecto.Type

  @moduledoc """
  Ecto type to aid casting values returned by the Flagsmith API that need to be
  compared. Since those values are weakly typed in different places and they need
  to be compared, it's necessary to be able to convert and assign a type to a value
  in order to when comparing that value with another one, the other one can be cast
  to the same type.

  This ecto type works as a struct containing the converted value in its correctly 
  typed format and a field `:type` containing the corresponding type, so that it's
  easier to then cast any other stringed type into the same format.
  """

  @impl Ecto.Type
  def type(), do: :map

  @type t() :: %__MODULE__{
          :value => String.t() | number() | boolean(),
          :type => :string | :decimal | :boolean | :semver
        }

  @derive {Jason.Encoder, only: [:value, :type]}

  @enforce_keys [:value, :type]
  defstruct [:value, :type]

  @impl Ecto.Type
  def load(data), do: cast(data)

  @impl Ecto.Type
  def cast(%__MODULE__{value: _, type: _} = data), do: {:ok, data}

  def cast(%{"value" => value, "type" => "decimal"}),
    do: {:ok, %__MODULE__{value: Decimal.new(value), type: :decimal}}

  def cast(%{"value" => value, "type" => type}),
    do: {:ok, %__MODULE__{value: value, type: String.to_existing_atom(type)}}

  def cast(data) when is_number(data),
    do: {:ok, %__MODULE__{value: convert_number(data), type: :decimal}}

  def cast(%Decimal{} = data),
    do: {:ok, %__MODULE__{value: data, type: :decimal}}

  def cast(data) when data in ["false", "true"],
    do: {:ok, %__MODULE__{value: String.to_existing_atom(data), type: :boolean}}

  def cast(data) when data in ["False", "True"],
    do:
      {:ok,
       %__MODULE__{value: String.downcase(data) |> String.to_existing_atom(), type: :boolean}}

  def cast(data) when data in [false, true],
    do: {:ok, %__MODULE__{value: data, type: :boolean}}

  def cast(data) when is_binary(data) do
    case String.ends_with?(data, ":semver") do
      true ->
        create_semver(data)

      false ->
        {:ok, %__MODULE__{value: data, type: :string}}
    end
  end

  def cast(_), do: :error

  @impl Ecto.Type
  def dump(%__MODULE__{value: _, type: _} = data), do: {:ok, data}
  def dump(%{"value" => _, "type" => _type} = data), do: {:ok, data}

  def dump(data) when is_number(data),
    do: {:ok, %__MODULE__{value: data, type: :decimal}}

  def dump(%Decimal{} = data),
    do: {:ok, %__MODULE__{value: Decimal.to_string(data), type: :decimal}}

  def dump(data) when data in ["false", "true"],
    do: {:ok, %__MODULE__{value: String.to_existing_atom(data), type: :boolean}}

  def dump(data) when data in ["False", "True"],
    do:
      {:ok,
       %__MODULE__{value: String.downcase(data) |> String.to_existing_atom(), type: :boolean}}

  def dump(data) when data in [false, true],
    do: {:ok, %__MODULE__{value: data, type: :boolean}}

  def dump(data) when is_binary(data),
    do: {:ok, %__MODULE__{value: data, type: :string}}

  def dump(_), do: :error

  @impl Ecto.Type
  def embed_as(_), do: :dump

  @impl Ecto.Type
  def equal?(term_1, term_1), do: true
  def equal?(term_1, term_2), do: get_term(term_1) == get_term(term_2)

  def convert_value_to(%__MODULE__{type: :boolean}, to_convert)
      when to_convert in ["false", "true", "False", "True"],
      do: cast(to_convert)

  def convert_value_to(%__MODULE__{type: :semver}, to_convert),
    do: Version.parse(to_convert)

  def convert_value_to(%__MODULE__{type: type}, to_convert),
    do: Ecto.Type.cast(type, to_convert)

  defp get_term(data) do
    case cast(data) do
      {:ok, value} -> value
      :error -> {:error, data}
    end
  end

  defp convert_number(data) when is_float(data),
    do: Decimal.from_float(data)

  defp convert_number(data) when is_integer(data) or is_binary(data),
    do: Decimal.new(data)

  def is_semver(data) when is_binary(data),
    do: String.ends_with?(data, ":semver")

  def is_semver(_), do: false

  def create_semver(%Version{} = version), do: {:ok, %__MODULE__{value: version, type: :semver}}

  def create_semver(data) when is_binary(data) do
    without_semver = String.replace_suffix(data, ":semver", "")
    semver = Version.parse!(without_semver)

    {:ok, %__MODULE__{value: semver, type: :semver}}
  end
end
