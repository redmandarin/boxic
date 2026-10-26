defmodule Boxic.DMN.ArithmeticContextTest do
  use ExUnit.Case, async: true

  alias Boxic.DMN
  alias Boxic.FEEL.ExternalFunctions

  @odd "1234567890123456789012345678901235"
  @rounded Decimal.new("1234567890123456789012345678901236")
  @third Decimal.new("0.3333333333333333333333333333333333")

  defmodule RaisingRegistry do
    def external_functions do
      Decimal.Context.set(%Decimal.Context{precision: 1, flags: [:rounded]})
      raise ArgumentError, "registry programming failure"
    end
  end

  test "ordinary/traced decisions, BKMs and services use fixed arithmetic and restore callers" do
    model = model()
    opts = [external_functions: ExternalFunctions.new()]

    entries = [
      {fn -> DMN.evaluate(model, "Half") end, @rounded},
      {fn -> DMN.evaluate(model, "Third", %{}) end, @third},
      {fn -> DMN.evaluate(model, "Third", %{}, opts) end, @third},
      {fn -> DMN.evaluate(model, "Nested") end, @third},
      {fn -> DMN.evaluate(model, "Sum") end, @rounded},
      {fn -> DMN.evaluate_with_trace(model, "Sum") end, @rounded},
      {fn -> DMN.evaluate_with_trace(model, "Nested", %{}, opts) end, @third},
      {fn -> DMN.evaluate_service(model, "Service", []) end,
       %{"Sum" => @rounded, "Third" => @third}},
      {fn -> DMN.evaluate_service(model, "Service", [], opts) end,
       %{"Sum" => @rounded, "Third" => @third}},
      {fn -> DMN.evaluate_service_with_trace(model, "Service", []) end,
       %{"Sum" => @rounded, "Third" => @third}},
      {fn -> DMN.evaluate_service_with_trace(model, "Service", [], opts) end,
       %{"Sum" => @rounded, "Third" => @third}}
    ]

    for caller <- caller_contexts() do
      Decimal.Context.with(caller, fn ->
        for {entry, expected} <- entries do
          case entry.() do
            {:ok, value} ->
              assert value === expected

            {:ok, value, trace} ->
              assert value === expected
              assert trace.result === expected
          end

          assert Decimal.Context.get() === caller
        end
      end)
    end
  end

  test "DMN SUM overflow is local numeric null, with actual traced rule outputs retained" do
    model = model()
    large = Decimal.new(1, 9, 6_144)

    for caller <- caller_contexts() do
      Decimal.Context.with(caller, fn ->
        assert {:ok, nil} = DMN.evaluate(model, "OverflowSum", %{"large" => large})
        assert Decimal.Context.get() === caller

        assert {:ok, nil, trace} =
                 DMN.evaluate_with_trace(model, "OverflowSum", %{"large" => large})

        assert Decimal.Context.get() === caller
        [table] = Enum.filter(trace.events, &(&1.kind == :table))
        assert table.status == :ok
        assert table.result == nil
        assert Enum.map(table.rules, & &1.result) == [large, large]
        assert Enum.map(table.contributing_rules, & &1.source_id) == ["overflow_1", "overflow_2"]
      end)
    end
  end

  test "preflight, lookup and registry failures restore context for each DMN entry point" do
    model = model()
    caller = hd(caller_contexts())

    Decimal.Context.with(caller, fn ->
      assert {:error, _} = DMN.evaluate(%{model | source_profile: :dmn_1_4}, "Half")
      assert Decimal.Context.get() === caller
      assert {:error, _, _} = DMN.evaluate_with_trace(%{model | source_profile: :dmn_1_4}, "Half")
      assert Decimal.Context.get() === caller
      assert {:error, _} = DMN.evaluate_service(model, "missing", [])
      assert Decimal.Context.get() === caller
      assert {:error, _, _} = DMN.evaluate_service_with_trace(model, "missing", [])
      assert Decimal.Context.get() === caller

      for entry <- [
            fn -> DMN.evaluate(model, "Half", %{}, external_functions: RaisingRegistry) end,
            fn ->
              DMN.evaluate_with_trace(model, "Half", %{}, external_functions: RaisingRegistry)
            end,
            fn ->
              DMN.evaluate_service(model, "Service", [], external_functions: RaisingRegistry)
            end,
            fn ->
              DMN.evaluate_service_with_trace(model, "Service", [],
                external_functions: RaisingRegistry
              )
            end
          ] do
        assert_raise ArgumentError, "registry programming failure", entry
        assert Decimal.Context.get() === caller
      end
    end)
  end

  test "reentrant traced and untraced DMN calls restore the enclosing arithmetic context" do
    model = model()
    owner = self()

    temporary = %Decimal.Context{
      precision: 3,
      rounding: :up,
      flags: [:inexact],
      traps: [:inexact]
    }

    registry =
      ExternalFunctions.new([
        {"nested",
         fn ->
           before = Decimal.Context.get()

           value =
             Decimal.Context.with(temporary, fn ->
               {:ok, value} = DMN.evaluate(model, "Third")
               {:ok, ^value, _trace} = DMN.evaluate_with_trace(model, "Third")
               send(owner, {:temporary_restored, Decimal.Context.get() === temporary})
               value
             end)

           send(
             owner,
             {:outer_restored, Decimal.Context.get() === before, before.precision,
              before.rounding}
           )

           value
         end, []}
      ])

    caller = hd(caller_contexts())

    Decimal.Context.with(caller, fn ->
      assert {:ok, @third, _trace} =
               DMN.evaluate_with_trace(model, "HostNested", %{}, external_functions: registry)

      assert Decimal.Context.get() === caller
      assert_receive {:temporary_restored, true}
      assert_receive {:outer_restored, true, 34, :half_even}
    end)
  end

  defp model do
    xml = """
    <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/" id="defs" name="Arithmetic" namespace="urn:arithmetic">
      <inputData id="large" name="large"><variable name="large" typeRef="number"/></inputData>
      <decision id="half" name="Half"><literalExpression><text>#{@odd} + 0.5</text></literalExpression></decision>
      <decision id="third" name="Third"><literalExpression><text>1 / 3</text></literalExpression></decision>
      <decision id="host" name="HostNested"><literalExpression><text>nested()</text></literalExpression></decision>
      <businessKnowledgeModel id="bkm" name="Divide"><encapsulatedLogic><formalParameter name="n"/><literalExpression><text>n / 3</text></literalExpression></encapsulatedLogic></businessKnowledgeModel>
      <decision id="nested" name="Nested"><knowledgeRequirement><requiredKnowledge href="#bkm"/></knowledgeRequirement><literalExpression><text>Divide(1)</text></literalExpression></decision>
      <decision id="sum" name="Sum">#{table("sum_table", [{"sum_1", @odd}, {"sum_2", "0.5"}])}</decision>
      <decision id="overflow" name="OverflowSum"><informationRequirement><requiredInput href="#large"/></informationRequirement>#{table("overflow_table", [{"overflow_1", "large"}, {"overflow_2", "large"}])}</decision>
      <decisionService id="service" name="Service"><outputDecision href="#sum"/><outputDecision href="#third"/></decisionService>
    </definitions>
    """

    {:ok, model} = DMN.load_xml(xml)
    model
  end

  defp table(id, outputs) do
    rules =
      Enum.map_join(outputs, fn {rule_id, text} ->
        "<rule id=\"#{rule_id}\"><inputEntry><text>-</text></inputEntry><outputEntry><text>#{text}</text></outputEntry></rule>"
      end)

    "<decisionTable id=\"#{id}\" hitPolicy=\"COLLECT\" aggregation=\"SUM\"><input><inputExpression><text>1</text></inputExpression></input><output/>#{rules}</decisionTable>"
  end

  defp caller_contexts do
    [
      %Decimal.Context{
        precision: 6,
        rounding: :down,
        emin: -9,
        emax: 9,
        flags: [:inexact],
        traps: [:rounded, :inexact, :overflow]
      },
      %Decimal.Context{precision: 50, rounding: :half_up, flags: [:rounded], traps: []}
    ]
  end
end
