defmodule Boxic.FEEL.MathematicsProfileTest do
  use ExUnit.Case, async: true
  alias Boxic.FEEL

  test "integer powers do not square after the last required multiplication" do
    for {source, expected} <- [
          {"1e6144 ** 1", Decimal.new(1, 1, 6144)},
          {"1e-6176 ** 1", Decimal.new(1, 1, -6176)},
          {"1e4000 ** -1", Decimal.new(1, 1, -4000)}
        ] do
      assert {:ok, result} = FEEL.evaluate(source)
      assert Decimal.equal?(result, expected)
    end
  end

  test "sqrt and stddev use qualified decimal precision across large exponents" do
    assert {:ok, value} = FEEL.evaluate("sqrt(2)")
    assert value == Decimal.new("1.414213562373095048801688724209698")
    assert {:ok, value} = FEEL.evaluate("sqrt(1e6000)")
    assert Decimal.equal?(value, Decimal.new(1, 1, 3000))
    assert {:ok, value} = FEEL.evaluate("stddev([1,2,3])")
    assert Decimal.equal?(value, 1)
    assert {:ok, value} = FEEL.evaluate("stddev([1,2])")
    assert value == Decimal.new("0.7071067811865475244008443621048490")
  end

  test "profile gate rejects deferred functions, aliases, dynamic powers and hidden branches" do
    for source <- [
          "exp(1)",
          "if false then log(2) else 1",
          "{f: exp, r: f(1)}",
          "2 ** 0.5",
          "2 ** x",
          "f(1)",
          "(function(x) x)(1)",
          "sort([1], f)",
          "2 ** 1025"
        ] do
      assert {:error, %FEEL.Error{code: :unsupported_profile}} = FEEL.Profile.validate(source)
    end

    for source <- ["mean([1,0,0])", "sqrt(2)", "stddev([1,2])", "2 ** -3", "2 ** 1024"] do
      assert :ok = FEEL.Profile.validate(source)
    end

    assert {:error, %FEEL.Error{code: :unsupported_profile}} =
             FEEL.Profile.validate("< exp(1), > 2", :unary_tests)

    assert :ok = FEEL.Profile.validate("not(< 1, > sqrt(4))", :unary_tests)
  end
end
