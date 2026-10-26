defmodule Boxic.FEEL.UnaryTestValidationTest do
  use ExUnit.Case, async: true

  alias Boxic.FEEL

  test "uses unary-test grammar without evaluating operands" do
    for source <- [
          "-",
          "< 18, >= 65",
          "not(< 18, >= 65)",
          "not (1, 2)",
          "[1..10], ]20..30[",
          ~s("a,b", "c"),
          "unknown(1, 2), >= missing",
          ">= if true then 1 else missing",
          "{a: 1, b: 2}",
          "/* comment */ -",
          "if true then 1 else missing"
        ] do
      assert :ok = FEEL.validate_unary_tests(source), source
    end
  end

  test "rejects malformed alternatives even after an unconditional match" do
    for source <- [
          "",
          " ",
          "if )",
          "<",
          "not()",
          "not(1,)",
          "1,",
          ",1",
          "-, 1",
          "1, if )",
          "[1..]",
          "1 2"
        ] do
      assert {:error, %Boxic.FEEL.Error{}} = FEEL.validate_unary_tests(source), source
    end
  end

  test "expressions and unary tests have distinct entry grammars" do
    assert {:error, _} = FEEL.parse("< 18, >= 65")
    assert :ok = FEEL.validate_unary_tests("< 18, >= 65")
    assert {:error, _} = FEEL.parse("-")
    assert :ok = FEEL.validate_unary_tests("-")
  end
end
