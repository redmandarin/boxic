defmodule Boxic.DMN.XMLEditorTest do
  use ExUnit.Case, async: true

  @namespace "https://www.omg.org/spec/DMN/20230324/MODEL/"
  @tck Path.expand("../../../vendor/dmn-tck/TestCases", __DIR__)

  test "preserves the full admitted document while changing an actual table output" do
    xml = table_xml()
    assert {:ok, original} = Boxic.DMN.load_xml(xml)
    assert {:error, errors} = Boxic.DMN.encode_xml(original)
    assert Enum.any?(errors, &(&1.code == :lossy_serialization))

    assert {:ok, edited} =
             Boxic.DMN.edit_xml(xml, %{
               table_id: "table",
               rule_id: "adult",
               output_id: "result",
               text: ~s("approved & eligible")
             })

    expected =
      String.replace(
        xml,
        ~s(<outputEntry><text>"adult"),
        ~s(<outputEntry><text>"approved &amp; eligible")
      )

    assert semantic_xml(edited) == semantic_xml(expected)
    assert edited =~ "<!--before-->"
    assert edited =~ "<!--after-->"
    assert edited =~ ~s(standalone="yes")
    assert {:ok, revised} = Boxic.DMN.load_xml(edited)

    assert {:ok, "approved & eligible"} =
             Boxic.DMN.evaluate(revised, "Eligibility", %{"Age" => Decimal.new(20)})

    assert {:ok, "adult"} =
             Boxic.DMN.evaluate(original, "Eligibility", %{"Age" => Decimal.new(20)})

    assert {:error, errors} = Boxic.DMN.encode_xml(revised)
    assert Enum.any?(errors, &(&1.code == :lossy_serialization))
  end

  test "input cells use correct unary grammar and change the matching boundary" do
    assert {:ok, xml} =
             Boxic.DMN.edit_xml(table_xml(), %{
               table_id: "table",
               rule_id: "adult",
               input_id: "age_clause",
               text: ">= 21"
             })

    assert {:ok, model} = Boxic.DMN.load_xml(xml)

    assert {:ok, "unknown"} =
             Boxic.DMN.evaluate(model, "Eligibility", %{"Age" => Decimal.new(20)})

    assert {:ok, "adult"} = Boxic.DMN.evaluate(model, "Eligibility", %{"Age" => Decimal.new(21)})

    assert_invalid_syntax(
      Boxic.DMN.edit_xml(table_xml(), %{
        table_id: "table",
        rule_id: "adult",
        input_id: "age_clause",
        text: "> )"
      })
    )
  end

  test "existing default and allowed-value tests can be selected by their own IDs" do
    for id <- ["allowed_type", "allowed_input", "allowed_output", "default"] do
      text = if id == "default", do: ~s("unknown"), else: "if )"
      result = Boxic.DMN.edit_xml(table_xml(), %{element_id: id, text: text})
      if id == "default", do: assert({:ok, _xml} = result), else: assert_invalid_syntax(result)
    end

    assert {:ok, xml} =
             Boxic.DMN.edit_xml(table_xml(), %{element_id: "default", text: ~s("changed default")})

    assert {:ok, model} = Boxic.DMN.load_xml(xml)

    assert {:ok, "changed default"} =
             Boxic.DMN.evaluate(model, "Eligibility", %{"Age" => Decimal.new(1)})
  end

  test "nested literal expressions retain scope and require an actual source ID" do
    xml =
      document_xml("""
      <decision id="d" name="D"><context id="ctx">
        <contextEntry><variable name="Local amount" typeRef="number"/><literalExpression id="value"><text>2</text></literalExpression></contextEntry>
        <contextEntry><literalExpression id="answer"><text>Local amount * 3</text></literalExpression></contextEntry>
      </context></decision>
      """)

    assert {:ok, revised} = Boxic.DMN.edit_xml(xml, %{element_id: "value", text: "4"})
    assert {:ok, model} = Boxic.DMN.load_xml(revised)
    assert {:ok, value} = Boxic.DMN.evaluate(model, "D")
    assert Decimal.equal?(value, 12)

    assert {:error, [%{code: :xml_edit_id_not_found}]} =
             Boxic.DMN.edit_xml(xml, %{element_id: "generated_0", text: "4"})
  end

  test "repairs malformed target syntax but rejects malformed untouched expressions" do
    xml =
      document_xml(
        ~s|<decision id="d" name="D"><literalExpression id="e"><text>if )</text></literalExpression></decision>|
      )

    assert {:ok, revised} = Boxic.DMN.edit_xml(xml, %{element_id: "e", text: "1"})
    assert {:ok, model} = Boxic.DMN.load_xml(revised)
    assert {:ok, value} = Boxic.DMN.evaluate(model, "D")
    assert Decimal.equal?(value, 1)
    xml = String.replace(table_xml(), ~s(<outputEntry><text>"adult"), "<outputEntry><text>if )")
    assert_invalid_syntax(Boxic.DMN.edit_xml(xml, %{element_id: "default", text: ~s("okay")}))
  end

  test "preserves explicit namespace prefixes, Unicode and escaping" do
    xml = """
    <dmn:definitions xmlns:dmn="#{@namespace}" name="M" namespace="urn:m">
      <dmn:description>Descripción &amp; notes</dmn:description>
      <dmn:decision id="d" name="D"><dmn:literalExpression id="e"><dmn:text><![CDATA["old"]]></dmn:text></dmn:literalExpression></dmn:decision>
    </dmn:definitions>
    """

    assert {:ok, revised} = Boxic.DMN.edit_xml(xml, %{element_id: "e", text: ~s("café < 2 & 3")})
    assert revised =~ "<dmn:definitions"
    assert revised =~ "<dmn:text>"
    assert {:ok, model} = Boxic.DMN.load_xml(revised)
    assert {:ok, "café < 2 & 3"} = Boxic.DMN.evaluate(model, "D")

    for prolog <- [~s(<?xml version="1.0"?>), ~s(<?xml version="1.0" standalone="no"?>)] do
      assert {:ok, revised} =
               Boxic.DMN.edit_xml(prolog <> xml, %{element_id: "e", text: ~s("updated")})

      assert {:ok, _model} = Boxic.DMN.load_xml(revised)
      if prolog =~ "standalone", do: assert(revised =~ ~s(standalone="no"))
    end
  end

  test "rejects absent/duplicate IDs and unsupported targets rather than guessing" do
    assert {:error, [%{code: :xml_edit_id_not_found}]} =
             Boxic.DMN.edit_xml(table_xml(), %{element_id: "absent", text: "1"})

    for id <- ["table", "adult", "annotation", "opaque_expression", "shape"] do
      assert {:error, [%{code: :unsupported_xml_edit_target}]} =
               Boxic.DMN.edit_xml(table_xml(), %{element_id: id, text: "1"})
    end

    duplicate = String.replace(table_xml(), ~s(id="default"), ~s(id="condition"))

    assert {:error, [%{code: :xml_edit_ambiguous_id}]} =
             Boxic.DMN.edit_xml(duplicate, %{element_id: "condition", text: "1"})
  end

  test "rejects wrong clause kinds and IDs from other tables" do
    assert {:error, [%{code: :unsupported_xml_edit_target}]} =
             Boxic.DMN.edit_xml(table_xml(), %{
               table_id: "table",
               rule_id: "adult",
               input_id: "result",
               text: "1"
             })

    other =
      ~s(<decision id="other" name="Other"><decisionTable id="other_table"><input id="foreign"><inputExpression><text>1</text></inputExpression></input><output/><rule id="other_rule"><inputEntry><text>-</text></inputEntry><outputEntry><text>1</text></outputEntry></rule></decisionTable></decision>)

    xml = String.replace(table_xml(), "</definitions>", other <> "</definitions>")

    assert {:error, [%{code: :unsupported_xml_edit_target}]} =
             Boxic.DMN.edit_xml(xml, %{
               table_id: "table",
               rule_id: "adult",
               input_id: "foreign",
               text: "1"
             })
  end

  test "refuses non-character payload children and missing text rather than altering structure" do
    for payload <- ["<text>1<!--retain--></text>", "<description>not an expression</description>"] do
      xml =
        document_xml(
          ~s(<decision id="d" name="D"><literalExpression id="e">#{payload}</literalExpression></decision>)
        )

      assert {:error, [%{code: :unsupported_xml_edit_target}]} =
               Boxic.DMN.edit_xml(xml, %{element_id: "e", text: "2"})
    end

    assert {:error, [%{code: :unsupported_xml_edit_target}]} =
             Boxic.DMN.edit_xml(table_xml(), %{decision_id: "d", text: "1"})
  end

  test "rejects request errors, forbidden XML, unsupported names and exporter losses" do
    for request <- [
          nil,
          %{},
          %{element_id: "default", text: 1},
          %{element_id: "default", text: "1", extra: true},
          %{element_id: "default", text: <<0>>}
        ] do
      assert {:error, [%{code: :invalid_xml_edit}]} = Boxic.DMN.edit_xml(table_xml(), request)
    end

    for opts <- [
          [imports: %{}, imports: %{}],
          [resolver: fn _ -> raise "must not run" end],
          [imports: []],
          :bad
        ] do
      assert {:error, [%{code: :invalid_xml_edit}]} =
               Boxic.DMN.edit_xml(table_xml(), %{element_id: "default", text: "1"}, opts)
    end

    assert {:error, [%{code: :doctype_forbidden}]} =
             Boxic.DMN.edit_xml("<!DOCTYPE definitions>" <> table_xml(), %{
               element_id: "default",
               text: "1"
             })

    assert {:error, [%{code: :xml_size_limit_exceeded}]} =
             Boxic.DMN.edit_xml(String.duplicate(" ", 5_000_001), %{
               element_id: "default",
               text: "1"
             })

    assert {:error, [%{code: :unsupported_xml_edit_document}]} =
             Boxic.DMN.edit_xml(
               String.replace(
                 table_xml(),
                 "<!--before-->",
                 "<?wedge-probe ignored?><!--before-->"
               ),
               %{
                 element_id: "default",
                 text: "1"
               }
             )

    assert {:error, [%{code: :unsupported_xml_edit_document}]} =
             Boxic.DMN.edit_xml(String.replace(table_xml(), "UTF-8", "ISO-8859-1"), %{
               element_id: "default",
               text: "1"
             })

    assert {:error, [%{code: :unsupported_xml_name}]} =
             Boxic.DMN.edit_xml(
               String.replace(table_xml(), "kie:label", "kie:unadmitted-name"),
               %{element_id: "default", text: "1"}
             )
  end

  test "a loader fidelity-loss fixture can be edited without granting writer fidelity" do
    path = Path.join(__DIR__, "fixtures/interchange/inspect_only_documentation.dmn")

    assert {:ok, edited} =
             Boxic.DMN.edit_xml(File.read!(path), %{
               element_id: "documented_expression",
               text: "2"
             })

    assert edited =~ "Content that the normalized writer does not retain."
    assert {:ok, model} = Boxic.DMN.load_xml(edited)
    assert {:ok, result} = Boxic.DMN.evaluate(model, "Documented")
    assert Decimal.equal?(result, 2)
    assert {:error, [%{code: :lossy_serialization} | _rest]} = Boxic.DMN.encode_xml(model)
  end

  test "all supported nested XML expression paths accept valid edits and reject invalid syntax" do
    literal = ~s(<literalExpression id="target"><text>1</text></literalExpression>)
    plain = ~s(<literalExpression><text>1</text></literalExpression>)
    boolean = ~s(<literalExpression><text>true</text></literalExpression>)
    source = ~s(<literalExpression><text>[1]</text></literalExpression>)

    expressions = [
      {"context", "<context><contextEntry>#{literal}</contextEntry></context>"},
      {"function", "<functionDefinition>#{literal}</functionDefinition>"},
      {"invocation function", "<invocation>#{literal}</invocation>"},
      {"invocation binding",
       "<invocation>#{plain}<binding><parameter name=\"x\"/>#{literal}</binding></invocation>"},
      {"relation", "<relation><column name=\"x\"/><row>#{literal}</row></relation>"},
      {"list", "<list>#{literal}</list>"},
      {"condition",
       "<conditional><if>#{literal}</if><then>#{plain}</then><else>#{plain}</else></conditional>"},
      {"then",
       "<conditional><if>#{boolean}</if><then>#{literal}</then><else>#{plain}</else></conditional>"},
      {"else",
       "<conditional><if>#{boolean}</if><then>#{plain}</then><else>#{literal}</else></conditional>"},
      {"filter source", "<filter><in>#{literal}</in><match>#{boolean}</match></filter>"},
      {"filter match", "<filter><in>#{source}</in><match>#{literal}</match></filter>"}
    ]

    iterators =
      for {kind, body} <- [{"for", "return"}, {"some", "satisfies"}, {"every", "satisfies"}],
          {position, input, result} <- [{"source", literal, plain}, {"body", source, literal}] do
        {"#{kind} #{position}",
         "<#{kind} iteratorVariable=\"x\"><in>#{input}</in><#{body}>#{result}</#{body}></#{kind}>"}
      end

    for {position, expression} <- expressions ++ iterators do
      xml = document_xml(~s(<decision id="d" name="D">#{expression}</decision>))

      assert {:ok, revised} = Boxic.DMN.edit_xml(xml, %{element_id: "target", text: "2"}),
             position

      expected =
        String.replace(xml, literal, String.replace(literal, "<text>1</text>", "<text>2</text>"))

      assert semantic_xml(revised) == semantic_xml(expected), position
      assert_invalid_syntax(Boxic.DMN.edit_xml(xml, %{element_id: "target", text: "if )"}))
    end

    bkm =
      document_xml(
        ~s(<businessKnowledgeModel id="b" name="B"><encapsulatedLogic>#{literal}</encapsulatedLogic></businessKnowledgeModel><decision id="d" name="D">#{plain}</decision>)
      )

    assert {:ok, _revised} = Boxic.DMN.edit_xml(bkm, %{element_id: "target", text: "2"})
    assert_invalid_syntax(Boxic.DMN.edit_xml(bkm, %{element_id: "target", text: "if )"}))
  end

  test "allowed-value positions support valid unary edits, including nested type components" do
    for {id, value} <- [
          {"allowed_type", ">= 1"},
          {"allowed_input", ">= 1"},
          {"allowed_output", ~s("adult", "unknown")}
        ] do
      assert {:ok, revised} = Boxic.DMN.edit_xml(table_xml(), %{element_id: id, text: value})
      assert {:ok, model} = Boxic.DMN.load_xml(revised)
      assert :ok = Boxic.DMN.validate(model, for: :evaluation)
    end

    xml =
      document_xml(
        ~s(<itemDefinition name="T"><itemComponent name="outer"><itemComponent name="inner"><typeRef>number</typeRef><allowedValues id="nested_allowed"><text>&gt;= 0</text></allowedValues></itemComponent></itemComponent></itemDefinition><decision id="d" name="D"><literalExpression><text>1</text></literalExpression></decision>)
      )

    assert {:ok, _revised} =
             Boxic.DMN.edit_xml(xml, %{element_id: "nested_allowed", text: ">= 1"})

    assert_invalid_syntax(Boxic.DMN.edit_xml(xml, %{element_id: "nested_allowed", text: "if )"}))
  end

  test "explicit import maps validate real imported models without editing them" do
    root = Path.join(__DIR__, "fixtures/imports")
    main = File.read!(Path.join(root, "main.dmn"))
    imported = File.read!(Path.join(root, "library.dmn"))
    assert {:ok, model} = Boxic.DMN.inspect_xml(imported)
    imports = %{model.definitions.namespace => imported}
    assert {:ok, _loaded} = Boxic.DMN.load_xml(main, imports: imports)
    # Only the root document's real ID is admissible; imported IDs are never searched.
    [root_decision | _rest] =
      :xmerl_xpath.string(
        ~c"//*[local-name()='decision']",
        elem(:xmerl_scan.string(:binary.bin_to_list(main)), 0)
      )

    id = xpath_string(~c"string(@id)", root_decision)

    value =
      xpath_string(
        ~c"string(*[local-name()='literalExpression']/*[local-name()='text'])",
        root_decision
      )

    assert {:ok, revised} =
             Boxic.DMN.edit_xml(main, %{decision_id: id, text: value}, imports: imports)

    assert semantic_xml(main) == semantic_xml(revised)
  end

  test "qualification TCK models retain all XML when a stable-ID text is set to its current value" do
    groups =
      ~w(0001-input-data-string 0002-input-data-number 0003-input-data-string-allowed-values 0004-simpletable-U 0008-LX-arithmetic 0010-multi-output-U 0114-min-collect-hitpolicy 0115-sum-collect-hitpolicy 0116-count-collect-hitpolicy 0119-multi-collect-hitpolicy)

    for group <- groups do
      [path] = Path.wildcard(Path.join([@tck, "compliance-level-2", group, "*.dmn"]))
      xml = File.read!(path)
      {root, _rest} = :xmerl_scan.string(:binary.bin_to_list(xml), namespace_conformant: true)

      request = tck_edit(root)
      assert {:ok, revised} = Boxic.DMN.edit_xml(xml, request), group
      assert semantic_xml(revised) == semantic_xml(xml), group
      assert {:ok, model} = Boxic.DMN.load_xml(revised)
      assert :ok = Boxic.DMN.validate(model, for: :evaluation)
      assert {:error, errors} = Boxic.DMN.encode_xml(model)
      assert Enum.any?(errors, &(&1.code == :lossy_serialization))
    end
  end

  defp tck_edit(root) do
    case :xmerl_xpath.string(
           ~c"//*[local-name()='literalExpression' or local-name()='inputEntry' or local-name()='outputEntry'][@id]",
           root
         ) do
      [entry | _rest] ->
        %{
          element_id: xpath_string(~c"string(@id)", entry),
          text: xpath_string(~c"string(*[local-name()='text'])", entry)
        }

      [] ->
        case :xmerl_xpath.string(
               ~c"//*[local-name()='decision'][*[local-name()='literalExpression']]",
               root
             ) do
          [decision | _rest] ->
            %{
              decision_id: xpath_string(~c"string(@id)", decision),
              text:
                xpath_string(
                  ~c"string(*[local-name()='literalExpression']/*[local-name()='text'])",
                  decision
                )
            }

          [] ->
            [table | _rest] = :xmerl_xpath.string(~c"//*[local-name()='decisionTable']", root)
            [rule | _rest] = :xmerl_xpath.string(~c"*[local-name()='rule']", table)
            [input | _rest] = :xmerl_xpath.string(~c"*[local-name()='input']", table)

            %{
              table_id: xpath_string(~c"string(@id)", table),
              rule_id: xpath_string(~c"string(@id)", rule),
              input_id: xpath_string(~c"string(@id)", input),
              text:
                xpath_string(
                  ~c"string(*[local-name()='inputEntry'][1]/*[local-name()='text'])",
                  rule
                )
            }
        end
    end
  end

  defp assert_invalid_syntax({:error, diagnostics}),
    do: assert(Enum.any?(diagnostics, &(&1.code == :invalid_feel_syntax)))

  defp table_xml do
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <!--before--><definitions xmlns="#{@namespace}" xmlns:kie="urn:opaque" xmlns:dmndi="https://www.omg.org/spec/DMN/20230324/DMNDI/" xmlns:dc="http://www.omg.org/spec/DMN/20180521/DC/" name="M" namespace="urn:m">
      <description>Descripción</description>
      <extensionElements><kie:label label="opaque"><kie:literalExpression id="opaque_expression"><kie:text>if )</kie:text></kie:literalExpression></kie:label></extensionElements>
      <itemDefinition name="AgeType"><typeRef>number</typeRef><allowedValues id="allowed_type"><text>&gt;= 0</text></allowedValues></itemDefinition>
      <inputData id="age" name="Age"><variable name="Age" typeRef="AgeType"/></inputData>
      <decision id="d" name="Eligibility"><description>Keep me</description><informationRequirement><requiredInput href="#age"/></informationRequirement>
        <decisionTable id="table" hitPolicy="UNIQUE">
          <input id="age_clause"><inputExpression id="condition"><text>Age</text></inputExpression><inputValues id="allowed_input"><text>&gt;= 0</text></inputValues></input>
          <output id="result" typeRef="string"><outputValues id="allowed_output"><text>"adult", "minor", "unknown", "changed default", "approved &amp; eligible"</text></outputValues><defaultOutputEntry id="default"><text>"unknown"</text></defaultOutputEntry></output>
          <annotation name="Note"/>
          <rule id="adult"><inputEntry><text>&gt;= 18</text></inputEntry><outputEntry><text>"adult"</text></outputEntry><annotationEntry><text>Keep rule note</text></annotationEntry></rule>
        </decisionTable>
      </decision>
      <textAnnotation id="annotation"><text>Keep annotation</text></textAnnotation>
      <dmndi:DMNDI><dmndi:DMNDiagram id="diagram"><dmndi:DMNShape id="shape" dmnElementRef="d"><dc:Bounds x="1" y="2" width="180" height="80"/></dmndi:DMNShape></dmndi:DMNDiagram></dmndi:DMNDI>
    </definitions><!--after-->
    """
  end

  defp document_xml(body),
    do: ~s(<definitions xmlns="#{@namespace}" name="M" namespace="urn:m">#{body}</definitions>)

  defp xpath_string(query, node) do
    {:xmlObj, :string, value} = :xmerl_xpath.string(query, node)
    to_string(value)
  end

  # Independent projection ignores parser location records, not XML content.
  defp semantic_xml(xml) do
    {document, _rest} =
      :xmerl_scan.string(:binary.bin_to_list(xml), namespace_conformant: true, document: true)

    semantic_node(document)
  end

  defp semantic_node({:xmlDocument, content}), do: Enum.map(content, &semantic_node/1)

  defp semantic_node(node) when elem(node, 0) == :xmlElement do
    attrs =
      node |> elem(7) |> Enum.map(fn attr -> {elem(attr, 1), elem(attr, 8)} end) |> Enum.sort()

    {elem(node, 1), elem(node, 2), attrs, Enum.map(elem(node, 8), &semantic_node/1)}
  end

  defp semantic_node(node) when elem(node, 0) == :xmlText, do: {:text, elem(node, 4)}
  defp semantic_node(node) when elem(node, 0) == :xmlComment, do: {:comment, elem(node, 4)}
  defp semantic_node(node) when elem(node, 0) == :xmlDecl, do: {:declaration, elem(node, 3)}
end
