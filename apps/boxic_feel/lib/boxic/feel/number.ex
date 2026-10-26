defmodule Boxic.FEEL.Number do
  @moduledoc false
  alias Boxic.FEEL.{Arithmetic, Error}

  @max_digits 8_192
  @max_exponent 20_000

  def parse(text) when is_binary(text) and byte_size(text) <= @max_digits do
    case Decimal.parse(text, max_digits: @max_digits, max_exponent: @max_exponent) do
      {number, ""} -> admit(number)
      _ -> invalid()
    end
  end

  def parse(_text), do: invalid()

  def admit(%Decimal{sign: sign, coef: coefficient, exp: exponent} = number)
      when sign in [-1, 1] and is_integer(coefficient) and coefficient >= 0 and
             is_integer(exponent) and abs(exponent) <= @max_exponent do
    if byte_size(Integer.to_string(coefficient)) <= @max_digits do
      Arithmetic.with_context(fn ->
        case Arithmetic.protect(fn -> {:ok, Decimal.apply_context(number)} end) do
          {:ok, %Decimal{} = value} -> {:ok, clamp(value)}
          {:ok, nil} -> invalid()
        end
      end)
    else
      invalid()
    end
  end

  def admit(%Decimal{}), do: invalid()

  def admit(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case admit(value) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  def admit(value) when is_tuple(value) do
    with {:ok, values} <- value |> Tuple.to_list() |> admit(),
         do: {:ok, List.to_tuple(values)}
  end

  def admit(values) when is_map(values) do
    Enum.reduce_while(Map.to_list(values), {:ok, values}, fn {key, value}, {:ok, acc} ->
      case admit(value) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        error -> {:halt, error}
      end
    end)
  end

  def admit(value), do: {:ok, value}

  # The same value may have many (coefficient, scale) representations. Decimal
  # uses adjusted exponent limits; DMN 10.3.2.3.1 also bounds the stored scale.
  defp clamp(%Decimal{coef: 0} = value), do: %{value | exp: min(6_111, max(-6_176, value.exp))}

  defp clamp(%Decimal{exp: exponent} = value) when exponent > 6_111,
    do: %{value | coef: value.coef * Integer.pow(10, exponent - 6_111), exp: 6_111}

  defp clamp(value), do: value

  defp invalid,
    do:
      {:error,
       Error.new(
         :invalid_number,
         "number is malformed, nonfinite, outside the FEEL domain or admission limits"
       )}
end
