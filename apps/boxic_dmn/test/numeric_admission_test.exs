defmodule Boxic.DMN.NumericAdmissionTest do
  use ExUnit.Case, async: true
  alias Boxic.DMN

  test "typed and untyped numeric inputs agree with source mapping and traces" do
    {:ok, model} =
      DMN.load_xml("""
      <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/" id="n" name="Numbers" namespace="urn:n">
        <inputData id="x" name="x"><variable name="x" typeRef="number"/></inputData>
        <decision id="d" name="D"><informationRequirement><requiredInput href="#x"/></informationRequirement><literalExpression><text>x</text></literalExpression></decision>
      </definitions>
      """)

    digits = "12345678901234567890123456789012345"
    {:ok, expected} = Boxic.FEEL.evaluate(digits)

    for value <- [digits, Decimal.new(1, String.to_integer(digits), 0)] do
      assert {:ok, ^expected} = DMN.evaluate(model, "D", %{"x" => value})
      assert {:ok, ^expected, trace} = DMN.evaluate_with_trace(model, "D", %{"x" => value})
      assert trace.result == expected
    end

    for value <- ["NaN", "Infinity", "1e6145", Decimal.new("NaN")] do
      assert {:error, error} = DMN.evaluate(model, "D", %{"x" => value})
      assert {:error, ^error, trace} = DMN.evaluate_with_trace(model, "D", %{"x" => value})
      assert trace.stage == :input_coercion
    end
  end
end
