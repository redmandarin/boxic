defmodule Boxic.FEEL.DynamicPowerTest do
  use ExUnit.Case, async: true
  alias Boxic.FEEL

  @opts [profile: :bounded_v1]

  test "source, AST, unary and bounded calls accept evaluated integer exponents" do
    {:ok, ast} = FEEL.parse("base ** exponent")
    caller = %Decimal.Context{precision: 2, rounding: :up, traps: [:inexact, :rounded]}

    Decimal.Context.with(caller, fn ->
      for {base, exponent, expected} <- [
            {"2", "3.00", "8"},
            {"2", "-3", "0.125"},
            {"2", "0", "1"},
            {"1", "1024", "1"},
            {"1", "-1024.0", "1"},
            {"1e6144", "1", "1e6144"},
            {"1e-6176", "1", "1e-6176"}
          ] do
        {:ok, base} = FEEL.evaluate(base)
        context = %{"base" => base, "exponent" => Decimal.new(exponent)}
        {:ok, expected} = FEEL.evaluate(expected)
        assert {:ok, ^expected} = FEEL.evaluate("base ** exponent", context, @opts)
        assert {:ok, ^expected} = FEEL.evaluate_ast(ast, context, @opts)
        assert {:ok, {:ok, ^expected}} = FEEL.evaluate_bounded("base ** exponent", context)

        assert {:ok, true} =
                 FEEL.evaluate_unary_test("= base ** exponent", expected, context, @opts)

        assert Decimal.Context.get() === caller
      end
    end)
  end

  test "runtime fractional/type/resource rejection and numeric-domain null are distinct" do
    for {exponent, code} <- [
          {"0.5", :unsupported_profile},
          {"-0.5", :unsupported_profile},
          {"1000000000.5", :unsupported_profile},
          {"1025", :execution_limit_exceeded},
          {"-1025", :execution_limit_exceeded},
          {"999999999", :execution_limit_exceeded},
          {"-999999999", :execution_limit_exceeded}
        ] do
      context = %{"n" => Decimal.new(exponent)}
      assert :ok = FEEL.Profile.validate("2 ** n")
      assert {:error, %FEEL.Error{code: ^code}} = FEEL.evaluate("2 ** n", context, @opts)
      assert {:ok, {:error, %FEEL.Error{code: ^code}}} = FEEL.evaluate_bounded("2 ** n", context)
    end

    for n <- [Decimal.new("1000000000"), Decimal.new("-1000000000"), Decimal.new(1, 1, 6144), nil] do
      assert {:ok, nil} = FEEL.evaluate("2 ** n", %{"n" => n}, @opts)
      assert {:ok, {:ok, nil}} = FEEL.evaluate_bounded("2 ** n", %{"n" => n})
    end

    assert {:error, %FEEL.Error{code: :type_error}} =
             FEEL.evaluate("2 ** n", %{"n" => true}, @opts)

    assert {:ok, nil} = FEEL.evaluate("0 ** n", %{"n" => Decimal.new(-1)}, @opts)
    assert {:ok, nil} = FEEL.evaluate("1e4000 ** n", %{"n" => Decimal.new(2)}, @opts)
  end

  test "computed exponents inherit scope and skipped work has no runtime check" do
    assert {:ok, value} = FEEL.evaluate("2 ** (n + 1)", %{"n" => Decimal.new(2)}, @opts)
    assert Decimal.equal?(value, 8)
    assert {:ok, values} = FEEL.evaluate("for n in [0,1,2] return 2 ** n", %{}, @opts)
    assert Enum.map(values, &Decimal.to_integer/1) == [1, 2, 4]

    assert {:ok, value} =
             FEEL.evaluate("if false then 2 ** n else 7", %{"n" => Decimal.new("0.5")}, @opts)

    assert Decimal.equal?(value, 7)

    assert {:error, %FEEL.Error{code: :unsupported_profile}} =
             FEEL.Profile.validate("if false then 2 ** 0.5 else 7")

    assert {:error, %FEEL.Error{code: :unsupported_profile}} =
             FEEL.Profile.validate("2 ** (if flag then exp(1) else n)")
  end

  test "unprofiled legacy power capability remains available" do
    assert {:ok, result} = FEEL.evaluate("1 ** n", %{"n" => Decimal.new(1025)})
    assert Decimal.equal?(result, 1)
    assert {:ok, %Decimal{}} = FEEL.evaluate("2 ** n", %{"n" => Decimal.new("0.5")})
    assert {:error, %FEEL.Error{code: :unsupported_profile}} = FEEL.evaluate("exp(1)", %{}, @opts)

    assert {:error, %FEEL.Error{code: :invalid_option}} =
             FEEL.evaluate("1", %{}, profile: :unknown)
  end

  test "profile AST admission rejects callable and nonfinite literals" do
    assert {:error, %FEEL.Error{code: :unsupported_profile}} =
             FEEL.evaluate_ast({:literal, fn -> 1 end}, %{}, @opts)

    assert {:error, %FEEL.Error{code: :invalid_number}} =
             FEEL.evaluate_ast(
               {:binary, :pow, {:literal, Decimal.new(2)}, {:literal, Decimal.new("NaN")}},
               %{},
               @opts
             )
  end
end
