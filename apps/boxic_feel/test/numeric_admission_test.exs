defmodule Boxic.FEEL.NumericAdmissionTest do
  use ExUnit.Case, async: true
  alias Boxic.FEEL

  test "literal, AST, context and number string use one nearest-even mapping" do
    spelling = "12345678901234567890123456789012345"
    raw = Decimal.new(1, String.to_integer(spelling), 0)
    expected = Decimal.new(1, 1_234_567_890_123_456_789_012_345_678_901_234, 1)

    for callback <- [
          fn -> FEEL.evaluate(spelling) end,
          fn -> FEEL.evaluate_ast({:literal, raw}, %{}) end,
          fn -> FEEL.evaluate("x", %{"x" => raw}) end,
          fn -> FEEL.evaluate(~s|number("#{spelling}")|) end
        ] do
      assert {:ok, ^expected} = callback.()
    end

    assert {:ok, value} = FEEL.evaluate("99999999999999999999999999999999995")
    assert Decimal.equal?(value, Decimal.new(1, 1, 35))
  end

  test "bounded malformed/out-of-domain admission is an error, numeric domain failure is null" do
    for source <- ["1e6145", "1e-6177", String.duplicate("1", 8193)] do
      assert {:error, %FEEL.Error{code: :invalid_number}} = FEEL.evaluate(source)
    end

    for value <- [Decimal.new("NaN"), Decimal.new("Inf"), Decimal.new(1, 1, 6145)] do
      assert {:error, %FEEL.Error{code: :invalid_number}} = FEEL.evaluate("x", %{"x" => [value]})

      assert {:error, %FEEL.Error{code: :invalid_number}} =
               FEEL.evaluate_ast({:literal, value}, %{})
    end

    assert {:ok, nil} = FEEL.evaluate(~s|number("NaN")|)
    assert {:ok, nil} = FEEL.evaluate("1 / 0")
  end

  test "scale boundaries retain exact subnormals and reject inexact underflow locally" do
    for source <- ["1e-6176", "1e-6176 * 1", "1e-6143 / 10"] do
      assert {:ok, %Decimal{coef: 1, exp: exponent}} = FEEL.evaluate(source)
      assert exponent in [-6176, -6144]
    end

    assert {:ok, [nil, one]} = FEEL.evaluate("[1e-6176 / 10, 1]")
    assert Decimal.equal?(one, 1)
    assert {:ok, max} = FEEL.evaluate("1e6144")
    assert max.exp == 6111
    assert Decimal.equal?(max, Decimal.new(1, 1, 6144))
  end

  test "mean retains the arithmetic context precision" do
    assert {:ok, value} = FEEL.evaluate("mean([1,0,0])")
    assert value == Decimal.new("0.3333333333333333333333333333333333")
  end

  test "nonfinite host results cannot escape admission" do
    registry =
      FEEL.ExternalFunctions.new([
        {"bad", fn -> [%{"x" => {Decimal.new("NaN")}}] end, returns: :feel}
      ])

    assert {:error, %FEEL.Error{code: :invalid_number}} =
             FEEL.evaluate("bad()", %{}, external_functions: registry)
  end

  test "fractional duration construction is bounded, rounded and never leaks constructor failures" do
    caller = %Decimal.Context{precision: 2, rounding: :up, traps: [:inexact]}

    Decimal.Context.with(caller, fn ->
      spelling = "PT0.12345678901234567890123456789012345S"
      assert {:ok, duration} = FEEL.evaluate(~s|@"#{spelling}"|)
      assert duration.seconds == Decimal.new("0.1234567890123456789012345678901234")
      assert {:ok, ^duration} = FEEL.evaluate(~s|duration("#{spelling}")|)
      assert Decimal.Context.get() === caller

      for value <- ["Pinvalid", "PT" <> String.duplicate("1", 8193) <> "S", "2020-99-99"] do
        assert {:error, %FEEL.Error{code: :invalid_syntax}} = FEEL.parse(~s|@"#{value}"|)
        assert Decimal.Context.get() === caller
      end
    end)
  end
end
