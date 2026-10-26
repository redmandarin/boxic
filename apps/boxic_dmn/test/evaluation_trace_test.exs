defmodule Boxic.DMN.EvaluationTraceTest do
  use ExUnit.Case, async: true

  alias Boxic.DMN
  alias Boxic.DMN.Model
  alias Boxic.FEEL.ExternalFunctions

  @policies ["UNIQUE", "FIRST", "ANY", "PRIORITY", "RULE ORDER", "OUTPUT ORDER", "COLLECT"]

  for policy <- @policies do
    test "#{policy} preserves result and records actual matches versus contributions" do
      policy = unquote(policy)

      rules =
        if policy == "UNIQUE",
          do: [{"-", "1"}, {"0", "2"}],
          else: [{"-", "1"}, {"-", if(policy == "ANY", do: "1", else: "2")}]

      {rules, opts} =
        if policy in ["PRIORITY", "OUTPUT ORDER"] do
          {[{"-", ~s("low")}, {"-", ~s("high")}], [priorities: ~s("high", "low")]}
        else
          {rules, []}
        end

      model = table_model(policy, rules, opts)
      trace = equivalent(model)
      table = only_table(trace)
      assert table.status == :ok

      assert table.inputs == [
               %{source_id: "input", position: 0, text: "1", status: :ok, value: Decimal.new(1)}
             ]

      expected_matches = if policy == "UNIQUE", do: [0], else: [0, 1]
      assert positions(table.matched_rules) == expected_matches

      expected =
        case policy do
          "FIRST" -> [0]
          "PRIORITY" -> [1]
          "OUTPUT ORDER" -> [1, 0]
          _ -> expected_matches
        end

      assert positions(table.contributing_rules) == expected
      assert Enum.all?(table.matched_rules, &(&1.source_id == "rule_#{&1.position}"))
      assert table.outcome == :matched
      assert hd(table.rules).outputs |> hd() |> Map.fetch!(:status) == :ok
      assert trace.result == table.result
      assert trace.truncated == false
      assert Enum.map(trace.events, & &1.event_id) == Enum.to_list(1..length(trace.events))
      assert hd(trace.events).kind == :decision
      assert Enum.any?(trace.events, &(&1.parent_id == hd(trace.events).event_id))
    end
  end

  for aggregation <- ["SUM", "MIN", "MAX", "COUNT"] do
    test "COLLECT #{aggregation} records every consumed operand" do
      trace =
        equivalent(
          table_model("COLLECT", [{"-", "1"}, {"-", "2"}], aggregation: unquote(aggregation))
        )

      assert positions(only_table(trace).contributing_rules) == [0, 1]
    end
  end

  test "FIRST still evaluates all matching outputs and does not evaluate unmatched outputs" do
    registry = registry()

    model =
      table_model("FIRST", [{"-", "tick(1)"}, {"-", "tick(2)"}, {"0", "if )"}], input: "tick(9)")

    assert {:ok, Decimal.new(1)} ==
             DMN.evaluate(model, "Result", %{}, external_functions: registry)

    assert_calls([9, 1, 2])

    assert {:ok, value, trace} =
             DMN.evaluate_with_trace(model, "Result", %{}, external_functions: registry)

    assert value == Decimal.new(1)
    assert_calls([9, 1, 2])
    table = only_table(trace)
    assert positions(table.matched_rules) == [0, 1]
    assert positions(table.contributing_rules) == [0]
    assert Enum.at(table.rules, 1).output_status == :ok
    assert Enum.at(table.rules, 2).status == :not_matched

    assert Enum.at(table.rules, 2).outputs == [
             %{position: 0, text: "if )", status: :not_evaluated, reason: :rule_not_matched}
           ]
  end

  test "PRIORITY and OUTPUT ORDER reuse the priorities evaluated during reduction" do
    registry =
      ExternalFunctions.new([
        {"priority",
         fn value ->
           send(self(), {:tick, Decimal.to_integer(value)})
           if Decimal.equal?(value, Decimal.new(1)), do: "low", else: "high"
         end, []}
      ])

    for policy <- ["PRIORITY", "OUTPUT ORDER"] do
      model =
        table_model(policy, [{"-", ~s("low")}, {"-", ~s("high")}],
          priorities: "priority(2), priority(1)"
        )

      trace = equivalent(model, external_functions: registry)
      assert_calls([2, 1, 2, 1])
      table = only_table(trace)
      assert table.priority_order == [1, 0]

      assert positions(table.contributing_rules) ==
               if(policy == "PRIORITY", do: [1], else: [1, 0])
    end
  end

  test "numeric priority's existing Decimal/map ranking defect remains separate" do
    for policy <- ["PRIORITY", "OUTPUT ORDER"] do
      trace = equivalent(table_model(policy, [{"-", "1"}]))
      assert trace.error == :output_not_in_priority_values
      assert only_table(trace).contributing_rules == nil
    end
  end

  test "multi-output priority uses the real shaped results and preserves ties" do
    for policy <- ["PRIORITY", "OUTPUT ORDER"] do
      model = table_model(policy, [{"-", "1"}, {"-", "2"}, {"-", "2"}])
      table = model.decisions["decision"].expression

      outputs = [
        %Model.OutputClause{name: "score", allowed_values: "2, 1"},
        %Model.OutputClause{name: "description"}
      ]

      rules =
        Enum.map(table.rules, &%{&1 | output_entries: &1.output_entries ++ [~s("description")]})

      trace = model |> put_expression(%{table | outputs: outputs, rules: rules}) |> equivalent()
      assert only_table(trace).status == :ok
      expected = if policy == "PRIORITY", do: [1], else: [1, 2, 0]
      assert positions(only_table(trace).contributing_rules) == expected

      assert hd(only_table(trace).rules).result == %{
               "score" => Decimal.new(1),
               "description" => "description"
             }
    end
  end

  for policy <- ["UNIQUE", "FIRST", "ANY", "PRIORITY", "COLLECT"] do
    test "#{policy} no-match and default paths preserve nil/default behavior" do
      policy = unquote(policy)

      for default <- [nil, "7"] do
        trace = equivalent(table_model(policy, [{"0", "if )"}], default: default))
        table = only_table(trace)
        assert table.matched_rules == []
        assert table.contributing_rules == []
        assert table.outcome == if(default, do: :default, else: :no_match)
        assert table.result == if(default, do: Decimal.new(7), else: nil)
        assert hd(table.defaults).status == if(default, do: :ok, else: :not_evaluated)
        assert hd(table.rules).output_status == :not_evaluated
      end
    end
  end

  test "empty ordered and aggregated tables preserve existing reduction behavior" do
    for policy <- ["RULE ORDER", "OUTPUT ORDER"] do
      table = table_model(policy, [{"0", "if )"}]) |> equivalent() |> only_table()
      assert table.result == []
      assert table.outcome == :no_match
      assert table.contributing_rules == []
    end

    for aggregation <- ["SUM", "MIN", "MAX", "COUNT"] do
      table =
        table_model("COLLECT", [{"0", "1"}], aggregation: aggregation)
        |> equivalent()
        |> only_table()

      assert table.result == nil
      assert table.outcome == :no_match
    end
  end

  test "hit-policy failures retain matched outputs with undetermined contributions" do
    for {policy, rules} <- [
          {"UNIQUE", [{"-", "1"}, {"-", "2"}]},
          {"ANY", [{"-", "1"}, {"-", "2"}]},
          {"PRIORITY", [{"-", "3"}]},
          {"COLLECT", [{"-", ~s("not a number")}]}
        ] do
      model = table_model(policy, rules, aggregation: if(policy == "COLLECT", do: "SUM"))
      trace = equivalent(model)
      table = only_table(trace)
      assert trace.status == :error
      assert table.status == :error
      assert table.phase == :hit_policy
      assert table.contributing_rules == nil
      assert Enum.all?(table.rules, &(&1.output_status == :ok))
      assert table.error == trace.error
    end
  end

  test "input and matching failures retain exact progress without inventing matches" do
    model = table_model("FIRST", [{"-", "1"}, {"if )", "2"}, {"-", "3"}])
    table = model |> equivalent() |> only_table()
    assert table.phase == :matching
    assert Enum.map(table.rules, & &1.status) == [:matched, :error, :not_evaluated]
    assert positions(table.matched_rules) == [0]
    assert Enum.all?(table.rules, &(&1.output_status == :not_evaluated))
    assert table.contributing_rules == nil

    model = table_model("FIRST", [{"-", "1"}], input: "if )")
    table = model |> equivalent() |> only_table()
    assert table.phase == :inputs
    assert hd(table.inputs).status == :error
    assert hd(table.rules).status == :not_evaluated
    assert table.matched_rules == []
    assert table.contributing_rules == nil
  end

  test "failure after earlier output cells and default cells preserves partial values" do
    for section <- [:rules, :defaults] do
      model = multi_output_model(section)
      table = model |> equivalent() |> only_table()
      cells = if section == :rules, do: hd(table.rules).outputs, else: table.defaults
      assert Enum.map(cells, & &1.status) == [:ok, :error, :not_evaluated]
      assert hd(cells).value == Decimal.new(1)
      assert table.contributing_rules == nil
      assert table.phase == if(section == :rules, do: :outputs, else: :defaults)
    end
  end

  test "incomplete defaults do not evaluate any default, even malformed text" do
    model = multi_output_model(:defaults)
    table = model.decisions["decision"].expression
    outputs = List.update_at(table.outputs, 2, &%{&1 | default_output: nil})
    trace = model |> put_expression(%{table | outputs: outputs}) |> equivalent()
    assert only_table(trace).outcome == :no_match
    assert trace.result == nil
    assert Enum.all?(only_table(trace).defaults, &(&1.status == :not_evaluated))
  end

  test "an input failure retains earlier values and later unevaluated cells" do
    model = table_model("FIRST", [{"-", "1"}])
    table = model.decisions["decision"].expression
    inputs = Enum.map(["1", "if )", "3"], &%Model.InputClause{expression: &1})

    table = %{
      table
      | inputs: inputs,
        rules: [%{hd(table.rules) | input_entries: ["-", "-", "-"]}]
    }

    trace = model |> put_expression(table) |> equivalent()
    assert Enum.map(only_table(trace).inputs, & &1.status) == [:ok, :error, :not_evaluated]
  end

  test "FIRST's later matched-output error remains an error" do
    model = table_model("FIRST", [{"-", "1"}, {"-", "if )"}, {"-", "3"}])
    table = model |> equivalent() |> only_table()
    assert Enum.map(table.rules, & &1.output_status) == [:ok, :error, :not_evaluated]
    assert positions(table.matched_rules) == [0, 1, 2]
    assert table.contributing_rules == nil
  end

  test "short-circuited conditions stay not evaluated" do
    model = table_model("FIRST", [{"0", "1"}])
    table = model.decisions["decision"].expression

    table = %{
      table
      | inputs: table.inputs ++ [%Model.InputClause{expression: "2"}],
        rules: [%{hd(table.rules) | input_entries: ["0", "if )"]}]
    }

    model = put_expression(model, table)
    trace = equivalent(model)
    assert Enum.map(hd(only_table(trace).rules).conditions, & &1.status) == [:ok, :not_evaluated]
  end

  test "dependencies distinguish evaluated, memoized and provided decisions" do
    model = graph_model()
    trace = equivalent(model, external_functions: registry())
    assert_calls([10, 10])
    decisions = events(trace, :decision)
    assert Enum.map(decisions, & &1.lookup_key) == ["root", "left", "seed", "right", "seed"]

    assert Enum.map(Enum.filter(decisions, &(&1.lookup_key == "seed")), & &1.execution) == [
             :evaluated,
             :memoized
           ]

    dependencies = events(trace, :dependency)
    assert Enum.any?(dependencies, &(&1.resolution == :memoized))
    assert Enum.all?(dependencies, &is_integer(&1.position))
    trace = equivalent(model, [], %{"Seed" => Decimal.new(5)})
    refute Enum.any?(events(trace, :decision), &(&1.lookup_key == "seed"))
    assert Enum.count(events(trace, :dependency), &(&1.resolution == :provided)) == 2
  end

  test "decision services use the same execution and shared dependency memo" do
    model = graph_model()

    for arguments <- [%{}, []] do
      ordinary = DMN.evaluate_service(model, "Service", arguments, external_functions: registry())

      assert {:ok, result, trace} =
               DMN.evaluate_service_with_trace(model, "Service", arguments,
                 external_functions: registry()
               )

      assert ordinary == {:ok, result}
      assert_calls([10, 10])
      assert length(events(trace, :service)) == 1
      assert Enum.count(events(trace, :decision), &(&1.execution == :memoized)) == 1
    end
  end

  test "missing inputs, cycles and final coercion failures preserve partial dependency evidence" do
    model = graph_model()

    seed = %{
      model.decisions["seed"]
      | requirements: [%Model.InformationRequirement{kind: :input_data, href: "input"}]
    }

    input = %Model.InputData{
      id: "input",
      name: "Required",
      variable: %Model.Variable{name: "Required"}
    }

    model = %{
      model
      | decisions: Map.put(model.decisions, "seed", seed),
        input_data: %{"input" => input}
    }

    trace = equivalent(model)
    assert trace.error == {:missing_input, "Required"}

    assert Enum.any?(
             events(trace, :dependency),
             &(&1.status == :error && &1.reference == "input")
           )

    model = graph_model()

    seed = %{
      model.decisions["seed"]
      | requirements: [%Model.InformationRequirement{kind: :decision, href: "root"}]
    }

    trace = equivalent(%{model | decisions: Map.put(model.decisions, "seed", seed)})
    assert trace.error == {:cyclic_decision_dependency, "root"}

    model = table_model("UNIQUE", [{"-", "1"}])

    decision = %{
      model.decisions["decision"]
      | variable: %Model.Variable{name: "Result", type_ref: "boolean"}
    }

    trace = equivalent(%{model | decisions: %{"decision" => decision}})
    assert only_table(trace).status == :ok
    assert hd(events(trace, :decision)).status == :error
  end

  test "upfront option, lookup, preflight and input-coercion errors retain empty traces" do
    model = table_model("UNIQUE", [{"-", "1"}])

    for {candidate, name, context, opts, stage} <- [
          {model, "missing", %{}, [], :lookup},
          {%{model | source_profile: :dmn_1_4}, "Result", %{}, [], :preflight},
          {model, "Result", %{},
           [external_functions: registry(), external_function_precedence: :invalid], :options}
        ] do
      ordinary = DMN.evaluate(candidate, name, context, opts)
      assert {:error, error, trace} = DMN.evaluate_with_trace(candidate, name, context, opts)
      assert ordinary == {:error, error}
      assert trace.events == []
      assert trace.stage == stage
    end

    input = %Model.InputData{
      id: "input",
      name: "Number",
      variable: %Model.Variable{name: "Number", type_ref: "number"}
    }

    model = %{model | input_data: %{"input" => input}}

    assert {:error, _, %{stage: :input_coercion, events: []}} =
             DMN.evaluate_with_trace(model, "Result", %{"Number" => "bad"})
  end

  test "missing source IDs remain nil with explicit positional and lookup fallbacks" do
    xml =
      document(
        ~s(<decision name="Result"><decisionTable><input><inputExpression><text>1</text></inputExpression></input><output/><rule><inputEntry><text>-</text></inputEntry><outputEntry><text>2</text></outputEntry></rule></decisionTable></decision>)
      )

    {:ok, model} = DMN.load_xml(xml)
    trace = equivalent(model)
    assert hd(events(trace, :decision)).source_id == nil
    assert hd(events(trace, :decision)).lookup_key == "Result"
    assert only_table(trace).source_id == nil
    assert only_table(trace).matched_rules == [%{source_id: nil, position: 0}]
  end

  test "boxed branches and repeated BKM tables reflect actual execution" do
    model = table_model("UNIQUE", [{"-", "tick(1)"}])

    conditional = %Model.ConditionalExpression{
      condition: literal("true"),
      then_branch: model.decisions["decision"].expression,
      else_branch: %{model.decisions["decision"].expression | id: "skipped_table"}
    }

    trace = model |> put_expression(conditional) |> equivalent(external_functions: registry())
    assert_calls([1, 1])
    assert length(events(trace, :table)) == 1

    assert Enum.any?(
             events(trace, :expression),
             &(&1.source_id == "skipped_table" && &1.status == :not_evaluated)
           )

    model = bkm_model()
    trace = equivalent(model)
    assert length(events(trace, :bkm)) == 2
    assert Enum.map(events(trace, :table), & &1.source_id) == ["bkm_table", "bkm_table"]

    assert Enum.map(events(trace, :table), &hd(&1.inputs).value) == [
             Decimal.new(1),
             Decimal.new(2)
           ]
  end

  test "nested BKM tables record cells on their own invocation" do
    model = bkm_model()
    outer = table_model("FIRST", [{"-", "Choose(2)"}]).decisions["decision"].expression
    trace = model |> put_expression(outer) |> equivalent()
    [parent, child] = events(trace, :table)
    assert parent.source_id == "table"
    assert child.source_id == "bkm_table"
    assert hd(child.inputs).value == Decimal.new(2)
    assert hd(hd(parent.rules).outputs).value == [Decimal.new(2)]
  end

  test "boxed quantifiers record skipped iterations without evaluating them" do
    for kind <- [:some, :every] do
      model = table_model("FIRST", [{"-", "1"}])
      body = if kind == :some, do: "tick(item) = 1", else: "tick(item) != 1"

      expression = %Model.IteratorExpression{
        kind: kind,
        variable: "item",
        source: literal("[1, 2, 3]"),
        body: literal(body)
      }

      trace = model |> put_expression(expression) |> equivalent(external_functions: registry())
      assert_calls([1, 1])

      [iterator] =
        Enum.filter(events(trace, :expression), &(&1.expression_kind == "IteratorExpression"))

      assert iterator.iterations_evaluated == 1
      assert iterator.iterations_not_evaluated == 2
    end
  end

  test "boxed invocation records its resolved BKM without a second execution" do
    model = bkm_model()

    invocation = %Model.Invocation{
      function: literal("Choose"),
      bindings: [%Model.Binding{parameter: "p", expression: literal("2")}]
    }

    trace = model |> put_expression(invocation) |> equivalent()
    assert only_table(trace).result == [Decimal.new(2)]

    assert Enum.any?(
             events(trace, :expression),
             &(Map.get(&1, :invoked_bkm, %{})[:source_id] == "bkm")
           )
  end

  test "registered host failures preserve redaction and partial table evidence" do
    registry = ExternalFunctions.new([{"fail", fn -> raise "private secret" end, []}])

    trace =
      table_model("FIRST", [{"-", "1"}, {"-", "fail()"}])
      |> equivalent(external_functions: registry)

    assert %Boxic.FEEL.Error{code: :external_function_error} = trace.error
    refute inspect(trace) =~ "private secret"
    assert hd(only_table(trace).rules).output_status == :ok
    assert Enum.at(only_table(trace).rules, 1).output_status == :error
  end

  test "a host boundary catching an interrupted BKM retains honest cell states" do
    model = bkm_model()
    bkm = model.bkms["bkm"]
    table = %{bkm.expression | rules: [%{hd(bkm.expression.rules) | output_entries: ["1 / 3"]}]}
    model = %{model | bkms: %{"bkm" => %{bkm | expression: table}}}
    model = put_expression(model, literal("host(Choose)"))

    registry =
      ExternalFunctions.new([
        {"host",
         fn {:external_function, function} ->
           {:ok, value} = function.([Decimal.new(1)])
           value
         end, []}
      ])

    Decimal.Context.with(%{Decimal.Context.get() | traps: [:inexact]}, fn ->
      trace = equivalent(model, external_functions: registry)
      assert %Boxic.FEEL.Error{code: :external_function_error} = trace.error
      table = only_table(trace)
      assert table.status == :interrupted
      assert hd(table.rules).status == :matched
      assert hd(table.rules).output_status == :interrupted
      assert hd(hd(table.rules).outputs).status == :interrupted
      assert table.contributing_rules == nil
    end)
  end

  test "nested ordinary and traced public calls do not contaminate the outer capture" do
    nested = table_model("UNIQUE", [{"-", "8"}])

    registry =
      ExternalFunctions.new([
        {"nested",
         fn ->
           {:ok, value} = DMN.evaluate(nested, "Result")
           {:ok, ^value, inner} = DMN.evaluate_with_trace(nested, "Result")
           send(self(), {:inner_trace, inner})
           value
         end, []}
      ])

    model = put_expression(nested, literal("nested()"))

    {:ok, value, trace} =
      DMN.evaluate_with_trace(model, "Result", %{}, external_functions: registry)

    assert value == Decimal.new(8)
    assert events(trace, :table) == []
    assert length(events(trace, :decision)) == 1
    assert_receive {:inner_trace, inner}
    assert length(events(inner, :table)) == 1
    assert hd(inner.events).parent_id == nil
    assert {:ok, ^value} = DMN.evaluate(nested, "Result")
    assert {:ok, ^value, next} = DMN.evaluate_with_trace(nested, "Result")
    assert hd(next.events).event_id == 1
  end

  test "propagated arithmetic exceptions leave later captures clean" do
    model = table_model("UNIQUE", [{"-", "1 / 3"}])

    Decimal.Context.with(%{Decimal.Context.get() | traps: [:inexact]}, fn ->
      assert_raise Decimal.Error, fn -> DMN.evaluate(model, "Result") end
      assert_raise Decimal.Error, fn -> DMN.evaluate_with_trace(model, "Result") end
    end)

    assert {:ok, _, trace} =
             DMN.evaluate_with_trace(table_model("UNIQUE", [{"-", "1"}]), "Result")

    assert hd(trace.events).event_id == 1
    assert hd(trace.events).parent_id == nil
  end

  defp equivalent(model, opts \\ [], context \\ %{}) do
    name = if Map.has_key?(model.decisions, "root"), do: "root", else: "Result"
    ordinary = DMN.evaluate(model, name, context, opts)
    {status, value, trace} = DMN.evaluate_with_trace(model, name, context, opts)
    assert {status, value} == ordinary
    assert trace.status == status
    trace
  end

  defp events(trace, kind), do: Enum.filter(trace.events, &(&1.kind == kind))

  defp only_table(trace) do
    [table] = events(trace, :table)
    table
  end

  defp positions(refs), do: Enum.map(refs, & &1.position)

  defp registry do
    ExternalFunctions.new([
      {"tick",
       fn value ->
         send(self(), {:tick, Decimal.to_integer(value)})
         value
       end, []}
    ])
  end

  defp assert_calls(values) do
    for value <- values, do: assert_receive({:tick, ^value})
    refute_receive {:tick, _}, 0
  end

  defp table_model(policy, rules, opts \\ []) do
    aggregation = if value = opts[:aggregation], do: ~s( aggregation="#{value}"), else: ""

    rules =
      rules
      |> Enum.with_index()
      |> Enum.map_join(fn {{test, output}, index} ->
        ~s(<rule id="rule_#{index}"><inputEntry><text>#{escape(test)}</text></inputEntry><outputEntry><text>#{escape(output)}</text></outputEntry></rule>)
      end)

    default =
      if value = opts[:default],
        do: "<defaultOutputEntry><text>#{escape(value)}</text></defaultOutputEntry>",
        else: ""

    xml =
      document("""
      <decision id="decision" name="Result"><decisionTable id="table" hitPolicy="#{policy}"#{aggregation}>
        <input id="input"><inputExpression><text>#{escape(opts[:input] || "1")}</text></inputExpression></input>
        <output id="output"><outputValues><text>#{escape(opts[:priorities] || "2, 1")}</text></outputValues>#{default}</output>
        #{rules}
      </decisionTable></decision>
      """)

    {:ok, model} = DMN.load_xml(xml)
    model
  end

  defp multi_output_model(section) do
    model = table_model("FIRST", [{if(section == :rules, do: "-", else: "0"), "1"}])
    table = model.decisions["decision"].expression
    values = ["1", "if )", "3"]

    outputs =
      Enum.with_index(values)
      |> Enum.map(fn {value, index} ->
        %Model.OutputClause{name: "output_#{index}", default_output: value}
      end)

    table = %{table | outputs: outputs, rules: [%{hd(table.rules) | output_entries: values}]}
    put_expression(model, table)
  end

  defp graph_model do
    xml =
      document("""
      <decision id="seed" name="Seed"><literalExpression><text>tick(10)</text></literalExpression></decision>
      <decision id="left" name="Left"><informationRequirement><requiredDecision href="#seed"/></informationRequirement><literalExpression><text>Seed + 1</text></literalExpression></decision>
      <decision id="right" name="Right"><informationRequirement><requiredDecision href="#seed"/></informationRequirement><literalExpression><text>Seed + 2</text></literalExpression></decision>
      <decision id="root" name="Root"><informationRequirement><requiredDecision href="#left"/></informationRequirement><informationRequirement><requiredDecision href="#right"/></informationRequirement><literalExpression><text>Left + Right</text></literalExpression></decision>
      <decisionService id="service" name="Service"><outputDecision href="#left"/><outputDecision href="#right"/></decisionService>
      """)

    {:ok, model} = DMN.load_xml(xml)
    model
  end

  defp bkm_model do
    model = table_model("COLLECT", [{"-", "p"}])

    table = %{
      model.decisions["decision"].expression
      | id: "bkm_table",
        inputs: [%Model.InputClause{expression: "p"}]
    }

    bkm = %Model.BusinessKnowledgeModel{
      id: "bkm",
      name: "Choose",
      parameters: [%Model.Variable{name: "p"}],
      expression: table
    }

    decision = %{
      model.decisions["decision"]
      | expression: literal("[Choose(1), Choose(2)]"),
        requirements: [%Model.InformationRequirement{kind: :knowledge, href: "bkm"}]
    }

    %{model | bkms: %{"bkm" => bkm}, decisions: %{"decision" => decision}}
  end

  defp put_expression(model, expression),
    do: %{
      model
      | decisions: Map.update!(model.decisions, "decision", &%{&1 | expression: expression})
    }

  defp literal(text), do: %Model.LiteralExpression{text: text}

  defp escape(text),
    do:
      text
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")

  defp document(body),
    do:
      ~s(<definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/" id="defs" name="Trace" namespace="urn:trace">#{body}</definitions>)
end
