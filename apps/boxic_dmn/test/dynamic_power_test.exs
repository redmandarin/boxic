defmodule Boxic.DMN.DynamicPowerTest do
  use ExUnit.Case, async: true
  alias Boxic.DMN

  @opts [profile: :bounded_v1]

  defp model(source) do
    {:ok, model} =
      DMN.load_xml("""
      <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/" id="m" name="M" namespace="urn:powers">
        <inputData id="n" name="n"><variable name="n" typeRef="number"/></inputData>
        <decision id="power" name="Power"><informationRequirement><requiredInput href="#n"/></informationRequirement><literalExpression id="expr"><text>#{source}</text></literalExpression></decision>
        <decisionService id="service" name="Service"><outputDecision href="#power"/><inputData href="#n"/></decisionService>
      </definitions>
      """)

    model
  end

  test "ordinary, traced and bounded decisions/services share dynamic power outcomes" do
    model = model("2 ** n")
    assert :ok = DMN.validate(model, for: :evaluation, profile: :bounded_v1)

    for n <- ["3.0", "-3", "0", "0.5", "1025", "1000000000"] do
      inputs = %{"n" => Decimal.new(n)}
      ordinary = DMN.evaluate(model, "Power", inputs, @opts)
      assert {status, result} = ordinary
      assert {^status, ^result, trace} = DMN.evaluate_with_trace(model, "Power", inputs, @opts)
      assert trace.status == status
      assert {:ok, ^ordinary} = DMN.evaluate_bounded(model, "Power", inputs)

      assert {:ok, {^status, ^result, bounded_trace}} =
               DMN.evaluate_bounded(model, "Power", inputs, trace: true)

      assert bounded_trace == trace
      expression = Enum.find(trace.events, &(&1.kind == :expression and &1.source_id == "expr"))
      assert expression.status == status
      if status == :error, do: assert(expression.error == result)
      service = DMN.evaluate_service(model, "Service", inputs, @opts)
      assert {service_status, service_result} = service

      assert {^service_status, ^service_result, _} =
               DMN.evaluate_service_with_trace(model, "Service", inputs, @opts)

      assert {:ok, ^service} = DMN.evaluate_service_bounded(model, "Service", inputs)

      assert {:ok, {^service_status, ^service_result, _}} =
               DMN.evaluate_service_bounded(model, "Service", inputs, trace: true)
    end
  end

  test "table cells use runtime exponent checks and retain actual partial evidence" do
    model = model("2 ** n")
    power = model.decisions["power"]

    table = %DMN.Model.DecisionTable{
      id: "table",
      hit_policy: "UNIQUE",
      inputs: [%DMN.Model.InputClause{id: "input", expression: "n"}],
      outputs: [%DMN.Model.OutputClause{id: "output", name: "value"}],
      rules: [
        %DMN.Model.DecisionRule{id: "rule", input_entries: ["-"], output_entries: ["2 ** n"]}
      ]
    }

    model = %{model | decisions: %{"power" => %{power | expression: table}}}

    for {n, outcome} <- [{"3", :ok}, {"0.5", :error}, {"1025", :error}] do
      inputs = %{"n" => Decimal.new(n)}
      assert {^outcome, result} = DMN.evaluate(model, "Power", inputs, @opts)
      assert {^outcome, ^result, trace} = DMN.evaluate_with_trace(model, "Power", inputs, @opts)

      assert {:ok, {^outcome, ^result, ^trace}} =
               DMN.evaluate_bounded(model, "Power", inputs, trace: true)

      table = Enum.find(trace.events, &(&1.kind == :table))
      assert [%{source_id: "rule"}] = table.matched_rules
      assert hd(table.rules).output_status == outcome
      assert hd(hd(table.rules).outputs).status == outcome
      if outcome == :ok, do: assert(table.contributing_rules == table.matched_rules)
    end
  end

  test "same-model reusable decisions remain supported and execute once across consumers" do
    {:ok, model} =
      DMN.load_xml("""
      <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/" id="r" name="Reuse" namespace="urn:reuse">
        <inputData id="n" name="n"><variable name="n" typeRef="number"/></inputData>
        <decision id="shared" name="Shared"><informationRequirement><requiredInput href="#n"/></informationRequirement><literalExpression><text>2 ** n</text></literalExpression></decision>
        <decision id="left" name="Left"><informationRequirement><requiredDecision href="#shared"/></informationRequirement><literalExpression><text>Shared + 1</text></literalExpression></decision>
        <decision id="right" name="Right"><informationRequirement><requiredDecision href="#shared"/></informationRequirement><literalExpression><text>Shared + 2</text></literalExpression></decision>
        <decision id="total" name="Total"><informationRequirement><requiredDecision href="#left"/></informationRequirement><informationRequirement><requiredDecision href="#right"/></informationRequirement><literalExpression><text>Left + Right</text></literalExpression></decision>
      </definitions>
      """)

    assert :ok = DMN.validate(model, for: :evaluation, profile: :bounded_v1)
    inputs = %{"n" => Decimal.new(3)}
    assert {:ok, result} = DMN.evaluate(model, "Total", inputs, @opts)
    assert Decimal.equal?(result, 19)
    assert {:ok, ^result, trace} = DMN.evaluate_with_trace(model, "Total", inputs, @opts)
    shared = Enum.filter(trace.events, &(&1.kind == :decision and &1.source_id == "shared"))
    assert Enum.count(shared, &(&1.execution == :evaluated)) == 1
    assert Enum.count(shared, &(&1.execution == :memoized)) == 1

    assert {:ok, {:ok, ^result, ^trace}} =
             DMN.evaluate_bounded(model, "Total", inputs, trace: true)
  end
end
