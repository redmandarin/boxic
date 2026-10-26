defmodule Boxic.DMN.XML.Editor do
  @moduledoc false

  require Record
  alias Boxic.DMN.{Diagnostic, Validator}
  alias Boxic.DMN.XML.{Loader, SchemaValidator}

  Record.defrecordp(
    :element,
    :xmlElement,
    Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :attribute,
    :xmlAttribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :document,
    :xmlDocument,
    Record.extract(:xmlDocument, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :text,
    :xmlText,
    Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :declaration,
    :xmlDecl,
    Record.extract(:xmlDecl, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :comment,
    :xmlComment,
    Record.extract(:xmlComment, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :event,
    :xmerl_event,
    Record.extract(:xmerl_event, from_lib: "xmerl/include/xmerl.hrl")
  )

  @namespace :"https://www.omg.org/spec/DMN/20230324/MODEL/"
  @expressions ~w(literalExpression decisionTable context invocation functionDefinition relation list conditional filter for some every)a
  @text_positions ~w(literalExpression inputExpression inputEntry outputEntry defaultOutputEntry allowedValues inputValues outputValues)a

  @type edit ::
          %{element_id: String.t(), text: String.t()}
          | %{decision_id: String.t(), text: String.t()}
          | %{table_id: String.t(), rule_id: String.t(), input_id: String.t(), text: String.t()}
          | %{table_id: String.t(), rule_id: String.t(), output_id: String.t(), text: String.t()}

  @spec edit(String.t(), edit(), keyword()) ::
          {:ok, String.t()} | {:error, [Diagnostic.t()] | Loader.load_error()}
  def edit(xml, edit, opts) do
    with :ok <- validate_request(xml, edit, opts),
         :ok <- SchemaValidator.validate_safety(xml),
         :ok <- SchemaValidator.validate_inspection_names(xml),
         :ok <- reject_processing_instructions(xml),
         {:ok, source} <- parse_document(xml),
         :ok <- validate_document(source),
         {:ok, path} <- target_path(source, edit),
         {:ok, revised} <- replace_text(source, path, edit.text),
         {:ok, _model} <- Loader.load_xml(xml, opts),
         output = encode(revised),
         {:ok, reloaded} <- Loader.load_xml(output, opts),
         :ok <- Validator.validate(reloaded, for: :evaluation),
         {:ok, reparsed} <- parse_document(output),
         :ok <- validate_preservation(revised, reparsed) do
      {:ok, output}
    end
  end

  defp validate_request(xml, edit, opts) do
    valid_options? =
      is_list(opts) and Keyword.keyword?(opts) and Keyword.keys(opts) in [[], [:imports]]

    valid_imports? = valid_options? and is_map(Keyword.get(opts, :imports, %{}))

    if is_binary(xml) and String.valid?(xml) and valid_edit?(edit) and valid_imports? do
      :ok
    else
      error(
        :invalid_xml_edit,
        [],
        "Expected UTF-8 XML, one supported text edit and an optional imports map."
      )
    end
  end

  defp valid_edit?(%{text: value} = edit) when is_binary(value) do
    keys = edit |> Map.keys() |> Enum.sort()

    keys in [
      [:decision_id, :text],
      [:element_id, :text],
      [:input_id, :rule_id, :table_id, :text],
      [:output_id, :rule_id, :table_id, :text]
    ] and
      Enum.all?(edit, fn
        {:text, text} -> xml_text?(text)
        {_key, id} -> is_binary(id) and id != ""
      end)
  end

  defp valid_edit?(_edit), do: false

  defp xml_text?(value) do
    String.valid?(value) and
      Enum.all?(String.to_charlist(value), fn cp ->
        cp in [9, 10, 13] or cp in 0x20..0xD7FF or cp in 0xE000..0xFFFD or cp in 0x10000..0x10FFFF
      end)
  end

  defp reject_processing_instructions(xml) do
    event = fn
      {:processingInstruction, _target, _value}, _location, _state -> :processing_instruction
      _event, _location, state -> state
    end

    case :xmerl_sax_parser.stream(xml, event_fun: event, event_state: :ok) do
      {:ok, :ok, _rest} ->
        :ok

      {:ok, :processing_instruction, _rest} ->
        error(
          :unsupported_xml_edit_document,
          [],
          "Processing instructions cannot be preserved by the XML exporter."
        )

      _other ->
        error(:invalid_xml, [], "The XML document could not be parsed.")
    end
  end

  defp parse_document(xml) do
    # xmerl reports the declaration to event_fun but omits it from its returned
    # document. Carry it through the root hook rather than lose standalone.
    event_fun = fn
      event(event: :ended, data: declaration() = decl), scanner ->
        :xmerl_scan.event_state(decl, scanner)

      _event, scanner ->
        scanner
    end

    hook_fun = fn
      element(parents: []) = root, scanner ->
        decl = :xmerl_scan.event_state(scanner)
        {document(content: Enum.reject([decl, root], &is_nil/1)), scanner}

      node, scanner ->
        {node, scanner}
    end

    {parsed, rest} =
      :xmerl_scan.string(:binary.bin_to_list(xml), [
        {:namespace_conformant, true},
        {:allow_entities, false},
        {:document, true},
        {:event_fun, event_fun, nil},
        {:hook_fun, hook_fun}
      ])

    content =
      Enum.flat_map(document(parsed, :content), fn
        document(content: inner) -> inner
        node -> [node]
      end)

    if String.trim(to_string(rest)) == "",
      do: {:ok, document(content: content)},
      else: error(:trailing_xml_content, [], "Unexpected content after the XML document.")
  catch
    :exit, _reason -> error(:invalid_xml, [], "The XML document could not be parsed.")
  end

  defp validate_document(document(content: content)) do
    declarations = Enum.filter(content, &Record.is_record(&1, :xmlDecl))
    roots = Enum.filter(content, &Record.is_record(&1, :xmlElement))

    with :ok <- validate_declarations(declarations) do
      case roots do
        [root] -> SchemaValidator.validate_document(root)
        _other -> error(:invalid_xml, [], "Expected one XML root element.")
      end
    end
  end

  defp validate_declarations(declarations) do
    if Enum.all?(declarations, fn decl ->
         declaration(decl, :vsn) == ~c"1.0" and
           (declaration(decl, :encoding) in [:undefined, nil, []] or
              String.upcase(to_string(declaration(decl, :encoding))) == "UTF-8")
       end) do
      :ok
    else
      error(
        :unsupported_xml_edit_document,
        [],
        "Text editing supports XML 1.0 encoded as UTF-8 only."
      )
    end
  end

  defp target_path(source, %{element_id: id}) do
    with {:ok, {node, path}} <- find_id(index_ids(source), id),
         :ok <- supported_target(source, node, path) do
      {:ok, path}
    end
  end

  defp target_path(source, %{decision_id: id}) do
    with {:ok, {node, path}} <- find_id(index_ids(source), id) do
      case {local_name(node), dmn_children(node, [:literalExpression])} do
        {:decision, [{_literal, index}]} ->
          literal_path = path ++ [index]

          if MapSet.member?(supported_paths(source), literal_path),
            do: {:ok, literal_path},
            else:
              error(
                :unsupported_xml_edit_target,
                [:xml, id],
                "The decision is outside the supported expression tree."
              )

        _other ->
          error(
            :unsupported_xml_edit_target,
            [:xml, id],
            "Expected a decision with one direct literal expression."
          )
      end
    end
  end

  defp target_path(source, edit) do
    {clause_kind, clause_id, cell_kind} =
      case edit do
        %{input_id: id} -> {:input, id, :inputEntry}
        %{output_id: id} -> {:output, id, :outputEntry}
      end

    ids = index_ids(source)

    with {:ok, {table, table_path}} <- find_id(ids, edit.table_id),
         {:ok, {rule, rule_path}} <- find_id(ids, edit.rule_id),
         {:ok, {clause, clause_path}} <- find_id(ids, clause_id),
         :ok <-
           table_relationship(
             source,
             {table, table_path},
             {rule, rule_path},
             {clause, clause_path},
             clause_kind
           ),
         index =
           Enum.find_index(dmn_children(table, [clause_kind]), fn {node, _index} ->
             node == clause
           end),
         {_cell, cell_index} <- Enum.at(dmn_children(rule, [cell_kind]), index) do
      {:ok, rule_path ++ [cell_index]}
    else
      nil ->
        error(
          :unsupported_xml_edit_target,
          [:xml, edit.rule_id],
          "The rule does not contain the selected cell."
        )

      {:error, _diagnostics} = error ->
        error
    end
  end

  defp table_relationship(
         source,
         {table, table_path},
         {rule, rule_path},
         {clause, clause_path},
         clause_kind
       ) do
    if local_name(table) == :decisionTable and local_name(rule) == :rule and
         local_name(clause) == clause_kind and Enum.drop(rule_path, -1) == table_path and
         Enum.drop(clause_path, -1) == table_path and
         MapSet.member?(supported_paths(source), table_path) do
      :ok
    else
      error(
        :unsupported_xml_edit_target,
        [:xml, id(table), id(rule), id(clause)],
        "Expected a supported table with its own rule and input/output clause."
      )
    end
  end

  defp supported_target(source, node, path) do
    if local_name(node) in @text_positions and MapSet.member?(supported_paths(source), path),
      do: :ok,
      else:
        error(
          :unsupported_xml_edit_target,
          [:xml, id(node)],
          "The selected ID is not a supported expression text position."
        )
  end

  defp index_ids(source), do: index_ids(source, [], %{})

  defp index_ids(node, path, ids) do
    ids =
      case id(node) do
        nil -> ids
        id -> Map.update(ids, id, [{node, path}], &[{node, path} | &1])
      end

    node
    |> children()
    |> Enum.with_index()
    |> Enum.reduce(ids, fn {child, index}, ids -> index_ids(child, path ++ [index], ids) end)
  end

  defp find_id(ids, id) do
    case Map.get(ids, id, []) do
      [match] -> {:ok, match}
      [] -> error(:xml_edit_id_not_found, [:xml, id], "The requested XML ID does not exist.")
      _multiple -> error(:xml_edit_ambiguous_id, [:xml, id], "The requested XML ID is ambiguous.")
    end
  end

  defp supported_paths(document(content: content)) do
    content
    |> Enum.with_index()
    |> Enum.reduce(MapSet.new(), fn {node, index}, paths ->
      supported_paths(node, [index], paths)
    end)
  end

  defp supported_paths(element() = node, path, paths) do
    if local_name(node) do
      node
      |> dmn_children(supported_children(local_name(node)))
      |> Enum.reduce(MapSet.put(paths, path), fn {child, index}, paths ->
        supported_paths(child, path ++ [index], paths)
      end)
    else
      paths
    end
  end

  defp supported_paths(_node, _path, paths), do: paths

  # These edges follow the loader's normalized expression positions. Opaque
  # extensions and diagram/documentation descendants are deliberately unreachable.
  defp supported_children(:definitions), do: [:decision, :businessKnowledgeModel, :itemDefinition]
  defp supported_children(:decision), do: @expressions
  defp supported_children(:businessKnowledgeModel), do: [:encapsulatedLogic]
  defp supported_children(:encapsulatedLogic), do: @expressions

  defp supported_children(kind) when kind in [:itemDefinition, :itemComponent],
    do: [:allowedValues, :itemComponent]

  defp supported_children(:decisionTable), do: [:input, :output, :rule]
  defp supported_children(:input), do: [:inputExpression, :inputValues]
  defp supported_children(:output), do: [:outputValues, :defaultOutputEntry]
  defp supported_children(:rule), do: [:inputEntry, :outputEntry]
  defp supported_children(:context), do: [:contextEntry]

  defp supported_children(kind) when kind in [:contextEntry, :functionDefinition, :binding],
    do: @expressions

  defp supported_children(:invocation), do: [:literalExpression, :binding]
  defp supported_children(:relation), do: [:row]
  defp supported_children(kind) when kind in [:row, :list], do: [:literalExpression]
  defp supported_children(:conditional), do: [:if, :then, :else]
  defp supported_children(:filter), do: [:in, :match]
  defp supported_children(:for), do: [:in, :return]
  defp supported_children(kind) when kind in [:some, :every], do: [:in, :satisfies]

  defp supported_children(kind)
       when kind in [:if, :then, :else, :in, :match, :return, :satisfies], do: @expressions

  defp supported_children(_kind), do: []

  defp dmn_children(node, names) do
    node
    |> children()
    |> Enum.with_index()
    |> Enum.filter(fn {child, _index} -> local_name(child) in names end)
  end

  defp local_name(element(expanded_name: {@namespace, name})), do: name
  defp local_name(_node), do: nil

  defp id(element(attributes: attrs)) do
    Enum.find_value(attrs, fn
      attribute(name: :id, value: value) -> to_string(value)
      _attribute -> nil
    end)
  end

  defp id(_node), do: nil

  defp replace_text(source, path, replacement) do
    container = node_at(source, path)

    case dmn_children(container, [:text]) do
      [{text_node, index}] ->
        if Enum.all?(children(text_node), &Record.is_record(&1, :xmlText)) do
          content = [text(value: String.to_charlist(replacement))]

          {:ok, replace_node(source, path ++ [index], element(text_node, content: content))}
        else
          error(
            :unsupported_xml_edit_target,
            [:xml | path],
            "The text payload contains unsupported child markup."
          )
        end

      _other ->
        error(
          :unsupported_xml_edit_target,
          [:xml | path],
          "Expected exactly one existing DMN text child."
        )
    end
  end

  defp node_at(node, []), do: node
  defp node_at(node, [index | rest]), do: node_at(Enum.at(children(node), index), rest)

  defp replace_node(_node, [], replacement), do: replacement

  defp replace_node(node, [index | rest], replacement) do
    content = List.update_at(children(node), index, &replace_node(&1, rest, replacement))
    put_children(node, content)
  end

  defp children(document(content: content)), do: content
  defp children(element(content: content)), do: content
  defp children(_node), do: []
  defp put_children(document() = node, content), do: document(node, content: content)
  defp put_children(element() = node, content), do: element(node, content: content)

  defp encode(document(content: content)) do
    standalone =
      Enum.find_value(content, fn
        declaration(standalone: value) when value in [:yes, :no] -> " standalone=\"#{value}\""
        _node -> nil
      end)

    prolog =
      if Enum.any?(content, &Record.is_record(&1, :xmlDecl)),
        do: ~c"<?xml version=\"1.0\" encoding=\"UTF-8\"#{standalone}?>",
        else: []

    content |> :xmerl.export(:xmerl_xml, prolog: prolog) |> :unicode.characters_to_binary()
  end

  defp validate_preservation(expected, actual) do
    if snapshot(expected) == snapshot(actual),
      do: :ok,
      else:
        error(
          :xml_edit_preservation_failed,
          [:xml],
          "XML export changed content outside the supported preservation boundary."
        )
  end

  defp snapshot(document(content: content)), do: Enum.flat_map(content, &snapshot/1)
  defp snapshot(declaration(standalone: flag)), do: [{:declaration, flag}]

  defp snapshot(element(name: name, expanded_name: expanded, attributes: attrs, content: content)) do
    attrs =
      Enum.map(attrs, fn attribute(name: name, value: value) -> {name, value} end) |> Enum.sort()

    [{:element, name, expanded, attrs, Enum.flat_map(content, &snapshot/1)}]
  end

  defp snapshot(text(value: value)), do: [{:text, value}]
  defp snapshot(comment(value: value)), do: [{:comment, value}]

  defp error(code, path, message),
    do:
      {:error,
       [
         %Diagnostic{
           code: code,
           category: :serialization,
           path: path,
           message: message,
           source_profile: :dmn_1_5
         }
       ]}
end
