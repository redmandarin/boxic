defmodule Boxic.DMN.ExpressionValidationTest do
  use ExUnit.Case, async: true

  alias Boxic.DMN
  alias Boxic.DMN.Model

  alias Boxic.DMN.Model.{
    BusinessKnowledgeModel,
    ConditionalExpression,
    ContextEntry,
    ContextExpression
  }

  alias Boxic.DMN.Model.{DecisionTable, DecisionRule, FilterExpression, FunctionDefinition}

  alias Boxic.DMN.Model.{
    InputClause,
    Invocation,
    Binding,
    ItemComponent,
    ItemDefinition
  }

  alias Boxic.DMN.Model.{
    IteratorExpression,
    ListExpression,
    LiteralExpression,
    OutputClause,
    Relation,
    RelationColumn,
    Variable
  }

  @positions [
    :literal,
    :bkm,
    :context,
    :function_body,
    :invoked_function,
    :binding,
    :relation,
    :list,
    :condition,
    :then,
    :else,
    :filter_source,
    :filter_match,
    :for_source,
    :for_body,
    :some_source,
    :some_body,
    :every_source,
    :every_body,
    :table_input,
    :table_condition,
    :table_output,
    :table_default,
    :input_allowed,
    :output_allowed,
    :type_allowed,
    :component_allowed,
    :nested_component_allowed
  ]

  for position <- @positions do
    test "validates #{position} without evaluation and identifies malformed syntax" do
      position = unquote(position)
      valid = xml_round_trip(model_for(position, "1"))
      assert :ok = DMN.validate(valid, for: :evaluation)
      assert :ok = DMN.validate(valid, for: :authoring)

      model = xml_round_trip(model_for(position, "if )"))
      assert :ok = DMN.validate(model)
      assert {:error, diagnostics} = DMN.validate(model, for: :evaluation)
      assert [diagnostic] = Enum.filter(diagnostics, &(&1.category == :feel))
      assert diagnostic.code == :invalid_feel_syntax
      assert diagnostic.details.text == "if )"
      assert diagnostic.path != [:model, 0]
      assert Enum.any?(diagnostic.path, &(&1 in ["decision", "bkm", "Type"]))
      assert %Boxic.FEEL.Error{} = diagnostic.cause
      assert is_map(Boxic.DMN.Diagnostic.to_map(diagnostic))
    end
  end

  test "schema-valid malformed FEEL is rejected by capability preflight" do
    xml = document("<literalExpression id=\"literal\"><text>if )</text></literalExpression>")
    assert :ok = DMN.validate_xml_schema(xml)
    assert {:ok, model} = DMN.load_xml(xml)

    assert {:error, [%{category: :feel, path: [:decisions, "decision", :expression, :text]}]} =
             DMN.validate(model, for: :evaluation)

    assert {:error, %Boxic.FEEL.Error{code: :invalid_syntax}} = DMN.evaluate(model, "Result")
  end

  test "checks skipped boxed branches while ordinary evaluation retains its behavior" do
    model = model_for(:else, "if )")
    assert {:ok, %Decimal{}} = DMN.evaluate(model, "Result")
    assert {:error, [%{category: :feel}]} = DMN.validate(model, for: :evaluation)
  end

  test "checks unused defaults, unmatched outputs and short-circuited rule conditions" do
    default_model = model_for(:table_default, "if )")
    assert {:ok, Decimal.new(1)} == DMN.evaluate(default_model, "Result")

    assert {:error, [%{code: :invalid_feel_syntax}]} =
             DMN.validate(default_model, for: :evaluation)

    model = model_for(:table_output, "if )")
    table = model.decisions["decision"].expression
    rule = %{hd(table.rules) | input_entries: ["0"]}
    model = with_expression(model, %{table | rules: [rule]})
    assert {:ok, nil} = DMN.evaluate(model, "Result")
    assert {:error, [%{code: :invalid_feel_syntax}]} = DMN.validate(model, for: :evaluation)

    table = %{table | inputs: table.inputs ++ [%InputClause{expression: "1"}]}
    rule = %{rule | input_entries: ["0", "if )"], output_entries: ["1"]}
    model = with_expression(model, %{table | rules: [rule]})
    assert {:ok, nil} = DMN.evaluate(model, "Result")

    assert {:error,
            [%{path: [:decisions, "decision", :expression, :rules, "rule", :input_entries, 1]}]} =
             DMN.validate(model, for: :evaluation)
  end

  test "nested boxed expressions retain the full diagnostic position" do
    nested = %ListExpression{
      items: [
        %ContextExpression{
          entries: [
            %ContextEntry{expression: %FunctionDefinition{body: literal("if )")}}
          ]
        }
      ]
    }

    assert {:error,
            [%{path: [:decisions, "decision", :expression, :items, 0, :entries, 0, :body, :text]}]} =
             DMN.validate(with_expression(base_model(), nested), for: :evaluation)
  end

  test "syntax success does not resolve names, call functions or establish runtime success" do
    for text <- ["missing", "unregistered(1)", "1 / 0"] do
      model = model_for(:literal, text)
      assert :ok = DMN.validate(model, for: :evaluation)
    end

    assert {:error, _} = DMN.evaluate(model_for(:literal, "unregistered(1)"), "Result")
  end

  test "uses unary grammar in table conditions and all allowed-value positions" do
    for position <- [
          :table_condition,
          :input_allowed,
          :output_allowed,
          :type_allowed,
          :component_allowed,
          :nested_component_allowed
        ],
        text <- ["-", "< 18, >= 65", "not(< 18, >= 65)", ~s("a,b", "c")] do
      assert :ok = DMN.validate(model_for(position, text), for: :evaluation)
    end

    assert {:error,
            [%{path: [:decisions, "decision", :expression, :rules, "rule", :input_entries, 0]}]} =
             DMN.validate(model_for(:table_condition, "1, if )"), for: :evaluation)
  end

  test "declaration names and ordered boxed context scope do not need business inputs" do
    context = %ContextExpression{
      entries: [
        %ContextEntry{variable: %Variable{name: "loan amount"}, expression: literal("1")},
        %ContextEntry{
          expression: literal(~s(if "loan amount" = "loan amount" then loan amount else missing))
        }
      ]
    }

    model = with_expression(base_model(), context)
    assert :ok = DMN.validate(model, for: :evaluation)
    assert {:ok, Decimal.new(1)} == DMN.evaluate(model, "Result")

    # A later declaration must not repair the syntax of an earlier expression.
    reversed = %{
      context
      | entries: [
          %ContextEntry{variable: %Variable{name: "first"}, expression: literal("loan amount")},
          %ContextEntry{variable: %Variable{name: "loan amount"}, expression: literal("1")}
        ]
    }

    assert {:error, [%{category: :feel}]} =
             DMN.validate(with_expression(model, reversed), for: :evaluation)
  end

  test "BKM parameters, boxed functions and iterator variables are local declarations" do
    variable = %Variable{name: "loan amount"}
    model = base_model()

    bkm = %BusinessKnowledgeModel{
      id: "bkm",
      name: "Loan",
      parameters: [variable],
      expression: literal("loan amount")
    }

    assert :ok = DMN.validate(%{model | bkms: %{"bkm" => bkm}}, for: :evaluation)
    function = %FunctionDefinition{parameters: [variable], body: literal("loan amount")}
    assert :ok = DMN.validate(with_expression(model, function), for: :evaluation)

    iterator = %IteratorExpression{
      kind: :for,
      variable: "loan amount",
      source: literal("[1]"),
      body: literal("loan amount")
    }

    assert :ok = DMN.validate(with_expression(model, iterator), for: :evaluation)
    assert {:ok, [Decimal.new(1)]} == DMN.evaluate(with_expression(model, iterator), "Result")
  end

  test "declared input names and typed component names are available to parsing" do
    model = base_model()

    input = %Model.InputData{
      id: "input",
      name: "loan data",
      variable: %Variable{name: "loan data", type_ref: "Loan"}
    }

    item = %ItemDefinition{
      name: "Loan",
      components: [%ItemComponent{name: "loan amount", type_ref: "number"}]
    }

    model = %{model | input_data: %{"input" => input}, item_definitions: %{"Loan" => item}}

    assert :ok =
             DMN.validate(with_expression(model, literal("loan data.loan amount")),
               for: :evaluation
             )
  end

  test "TCK 0089 multiword import aliases remain valid without example inputs" do
    path =
      Path.expand(
        "../../../vendor/dmn-tck/TestCases/compliance-level-3/0089-nested-inputdata-imports/0089-nested-inputdata-imports.dmn",
        __DIR__
      )

    imports =
      path
      |> Path.dirname()
      |> Path.join("*.dmn")
      |> Path.wildcard()
      |> Enum.reject(&(&1 == path))
      |> Map.new(fn candidate ->
        xml = File.read!(candidate)
        {:ok, model} = DMN.inspect_xml(xml)
        {model.definitions.namespace, xml}
      end)

    assert {:ok, model} = DMN.load_xml(File.read!(path), imports: imports)
    assert :ok = DMN.validate(model, for: :evaluation)
  end

  test "boxed filters can reference multiword fields from literal and boxed sources" do
    record = %ContextExpression{
      entries: [
        %ContextEntry{variable: %Variable{name: "net profit"}, expression: literal("1")}
      ]
    }

    for source <- [literal("[{net profit: 1}]"), %ListExpression{items: [record]}] do
      filter = %FilterExpression{source: source, match: literal("net profit > 0")}
      model = with_expression(base_model(), filter)
      assert :ok = DMN.validate(model, for: :evaluation)
      assert {:ok, [%{"net profit" => Decimal.new(1)}]} == DMN.evaluate(model, "Result")
    end
  end

  test "unsupported constructs and languages remain distinct from syntax errors" do
    assert {:error, [%{code: :unsupported_expression, category: :evaluation_preflight}]} =
             DMN.validate(with_expression(base_model(), {:unsupported, "vendorExpression"}),
               for: :evaluation
             )

    expression = %{literal("if )") | expression_language: "JavaScript"}

    assert {:error, [%{code: :unsupported_expression_language}]} =
             DMN.validate(with_expression(base_model(), expression), for: :evaluation)

    table_model = model_for(:table_output, "if )")

    table_model = %{
      table_model
      | definitions: %{table_model.definitions | expression_language: "JavaScript"}
    }

    assert {:error, [%{code: :unsupported_expression_language}]} =
             DMN.validate(table_model, for: :evaluation)
  end

  defp model_for(:bkm, text) do
    model = base_model()

    %{
      model
      | bkms: %{
          "bkm" => %BusinessKnowledgeModel{id: "bkm", name: "BKM", expression: literal(text)}
        }
    }
  end

  defp model_for(position, text)
       when position in [:type_allowed, :component_allowed, :nested_component_allowed] do
    leaf = %ItemComponent{
      id: "component",
      name: "amount",
      type_ref: "number",
      allowed_values: text
    }

    item =
      case position do
        :type_allowed ->
          %ItemDefinition{name: "Type", type_ref: "number", allowed_values: text}

        :component_allowed ->
          %ItemDefinition{name: "Type", components: [leaf]}

        :nested_component_allowed ->
          %ItemDefinition{
            name: "Type",
            components: [%ItemComponent{name: "nested", components: [leaf]}]
          }
      end

    %{base_model() | item_definitions: %{"Type" => item}}
  end

  defp model_for(position, text) do
    expression = position_expression(position, text)
    with_expression(base_model(), expression)
  end

  defp position_expression(:literal, text), do: literal(text)

  defp position_expression(:context, text),
    do: %ContextExpression{entries: [%ContextEntry{expression: literal(text)}]}

  defp position_expression(:function_body, text), do: %FunctionDefinition{body: literal(text)}
  defp position_expression(:invoked_function, text), do: %Invocation{function: literal(text)}

  defp position_expression(:binding, text),
    do: %Invocation{
      function: literal("f"),
      bindings: [%Binding{parameter: "p", expression: literal(text)}]
    }

  defp position_expression(:relation, text),
    do: %Relation{columns: [%RelationColumn{name: "column"}], rows: [[literal(text)]]}

  defp position_expression(:list, text), do: %ListExpression{items: [literal(text)]}

  defp position_expression(position, text) when position in [:condition, :then, :else] do
    expression = %ConditionalExpression{
      condition: literal("true"),
      then_branch: literal("1"),
      else_branch: literal("2")
    }

    Map.put(
      expression,
      %{condition: :condition, then: :then_branch, else: :else_branch}[position],
      literal(text)
    )
  end

  defp position_expression(position, text) when position in [:filter_source, :filter_match] do
    expression = %FilterExpression{source: literal("[1]"), match: literal("true")}
    Map.put(expression, if(position == :filter_source, do: :source, else: :match), literal(text))
  end

  defp position_expression(position, text)
       when position in [
              :for_source,
              :for_body,
              :some_source,
              :some_body,
              :every_source,
              :every_body
            ] do
    {kind, field} =
      %{
        for_source: {:for, :source},
        for_body: {:for, :body},
        some_source: {:some, :source},
        some_body: {:some, :body},
        every_source: {:every, :source},
        every_body: {:every, :body}
      }[position]

    expression = %IteratorExpression{
      kind: kind,
      variable: "item",
      source: literal("[1]"),
      body: literal("true")
    }

    Map.put(expression, field, literal(text))
  end

  defp position_expression(position, text) do
    input = %InputClause{id: "input", expression: "1"}
    output = %OutputClause{id: "output", name: "result"}
    rule = %DecisionRule{id: "rule", input_entries: ["-"], output_entries: ["1"]}

    {input, output, rule} =
      case position do
        :table_input -> {%{input | expression: text}, output, rule}
        :table_condition -> {input, output, %{rule | input_entries: [text]}}
        :table_output -> {input, output, %{rule | output_entries: [text]}}
        :table_default -> {input, %{output | default_output: text}, rule}
        :input_allowed -> {%{input | allowed_values: text}, output, rule}
        :output_allowed -> {input, %{output | allowed_values: text}, rule}
      end

    %DecisionTable{
      id: "table",
      hit_policy: "UNIQUE",
      inputs: [input],
      outputs: [output],
      rules: [rule]
    }
  end

  defp xml_round_trip(model) do
    assert {:ok, xml} = DMN.encode_xml(model)
    assert {:ok, reloaded} = DMN.load_xml(xml)
    reloaded
  end

  defp literal(text), do: %LiteralExpression{text: text}

  defp with_expression(model, expression) do
    decision = %{model.decisions["decision"] | expression: expression}
    %{model | decisions: %{"decision" => decision}}
  end

  defp base_model do
    {:ok, model} = DMN.load_xml(document("<literalExpression><text>1</text></literalExpression>"))
    model
  end

  defp document(expression) do
    """
    <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/" id="definitions" name="Validation" namespace="urn:validation">
      <decision id="decision" name="Result">#{expression}</decision>
    </definitions>
    """
  end
end
