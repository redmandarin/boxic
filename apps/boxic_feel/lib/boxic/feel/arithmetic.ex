defmodule Boxic.FEEL.Arithmetic do
  @moduledoc false

  @numeric_failures [:invalid_operation, :division_by_zero, :overflow]

  # DMN 1.5, 10.3.2.3.1: decimal128 precision, nearest-even rounding.
  # This owns execution context, not literal/input admission or serialization.
  def with_context(callback) do
    context = %Decimal.Context{
      precision: 34,
      rounding: :half_even,
      emax: 6_144,
      emin: -6_143,
      flags: [],
      traps: @numeric_failures
    }

    Decimal.Context.with(context, callback)
  end

  # Operands/callback arguments must already be evaluated. Do not protect an
  # entire FEEL/DMN execution or a registered host function with this boundary.
  def protect(callback) do
    case callback.() do
      {:ok, %Decimal{} = value} = result ->
        if Decimal.nan?(value) or Decimal.inf?(value), do: {:ok, nil}, else: result

      result ->
        result
    end
  rescue
    error in Decimal.Error ->
      if error.signal in @numeric_failures,
        do: {:ok, nil},
        else: reraise(error, __STACKTRACE__)
  end

  # Only pure native numeric math is called here, never FEEL/host callbacks.
  def float_math(callback) do
    protect(callback)
  rescue
    ArithmeticError -> {:ok, nil}
  end
end
