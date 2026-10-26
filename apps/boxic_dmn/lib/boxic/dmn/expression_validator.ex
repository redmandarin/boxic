defmodule Boxic.DMN.ExpressionValidator do
  @moduledoc false

  alias Boxic.DMN.{Compatibility, Diagnostic, FEEL, Model}
  alias Boxic.DMN.Model.{ConditionalExpression, ContextExpression, DecisionTable}
  alias Boxic.DMN.Model.{FilterExpression, FunctionDefinition, Invocation, IteratorExpression}
  alias Boxic.DMN.Model.{ListExpression, LiteralExpression, Relation}

  def validate(%Model{} = model, profile \\ :general) do
    names =
      (Map.values(model.input_data) ++ Map.values(model.decisions) ++ Map.values(model.bkms))
      |> Enum.flat_map(fn node -> [node.name | variable_names(node.variable, model)] end)

    names = names ++ Enum.map(model.imports, fn {_namespace, import} -> import.name end)

    expressions =
      for {kind, nodes} <- [decisions: model.decisions, bkms: model.bkms],
          {id, node} <- Enum.sort(nodes),
          scope =
            names ++ Enum.flat_map(Map.get(node, :parameters, []), &variable_names(&1, model)),
          diagnostic <- expression(node.expression, model, scope, [kind, id, :expression]),
          do: diagnostic

    types =
      model.item_definitions
      |> Enum.sort()
      |> Enum.flat_map(fn {name, item} ->
        item_tests(item, model, names, [:item_definitions, name])
      end)

    Enum.flat_map(expressions ++ types, &validate_position(&1, model, profile))
  end

  defp expression(%LiteralExpression{} = literal, model, names, path) do
    if feel_language?(model, literal.expression_language),
      do: syntax(literal.text, :expression, model, names, path ++ [:text]),
      else: []
  end

  defp expression(%DecisionTable{} = table, model, names, path) do
    if feel_language?(model, nil), do: table_syntax(table, model, names, path), else: []
  end

  defp expression(%ContextExpression{entries: entries}, model, names, path) do
    {diagnostics, _names} =
      entries
      |> Enum.with_index()
      |> Enum.map_reduce(names, fn {entry, index}, scope ->
        diagnostics =
          expression(entry.expression, model, scope, path ++ [:entries, entry.id || index])

        {diagnostics,
         scope ++ variable_names(entry.variable, model) ++ result_names(entry.expression, model)}
      end)

    List.flatten(diagnostics)
  end

  defp expression(%FunctionDefinition{} = function, model, names, path) do
    scope = names ++ Enum.flat_map(function.parameters, &variable_names(&1, model))
    expression(function.body, model, scope, path ++ [:body])
  end

  defp expression(%Invocation{} = invocation, model, names, path) do
    expression(invocation.function, model, names, path ++ [:function]) ++
      Enum.flat_map(invocation.bindings, fn binding ->
        expression(binding.expression, model, names, path ++ [:bindings, binding.parameter])
      end)
  end

  defp expression(%Relation{rows: rows}, model, names, path) do
    rows
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, index} ->
      expression_entries(row, model, names, path ++ [:rows, index])
    end)
  end

  defp expression(%ListExpression{items: items}, model, names, path),
    do: expression_entries(items, model, names, path ++ [:items])

  defp expression(%ConditionalExpression{} = conditional, model, names, path) do
    expression(conditional.condition, model, names, path ++ [:condition]) ++
      expression(conditional.then_branch, model, names, path ++ [:then]) ++
      expression(conditional.else_branch, model, names, path ++ [:else])
  end

  defp expression(%FilterExpression{} = filter, model, names, path) do
    expression(filter.source, model, names, path ++ [:source]) ++
      expression(
        filter.match,
        model,
        names ++ result_names(filter.source, model),
        path ++ [:match]
      )
  end

  defp expression(%IteratorExpression{} = iterator, model, names, path) do
    expression(iterator.source, model, names, path ++ [:source]) ++
      expression(
        iterator.body,
        model,
        [iterator.variable | names] ++ result_names(iterator.source, model),
        path ++ [:body]
      )
  end

  # Structural validation owns absent and unsupported expressions. Do not
  # mislabel those as malformed FEEL or attempt to execute them.
  defp expression(nil, _model, _names, _path), do: []
  defp expression({:unsupported, _kind}, _model, _names, _path), do: []

  defp table_syntax(table, model, names, path) do
    inputs =
      table.inputs
      |> Enum.with_index()
      |> Enum.flat_map(fn {input, index} ->
        position = path ++ [:inputs, input.id || index]

        syntax(input.expression, :expression, model, names, position ++ [:expression]) ++
          syntax(input.allowed_values, :unary_tests, model, names, position ++ [:allowed_values])
      end)

    outputs =
      table.outputs
      |> Enum.with_index()
      |> Enum.flat_map(fn {output, index} ->
        position = path ++ [:outputs, output.id || index]

        syntax(output.default_output, :expression, model, names, position ++ [:default_output]) ++
          syntax(output.allowed_values, :unary_tests, model, names, position ++ [:allowed_values])
      end)

    rules =
      table.rules
      |> Enum.with_index()
      |> Enum.flat_map(fn {rule, index} ->
        position = path ++ [:rules, rule.id || index]

        text_entries(rule.input_entries, :unary_tests, model, names, position ++ [:input_entries]) ++
          text_entries(
            rule.output_entries,
            :expression,
            model,
            names,
            position ++ [:output_entries]
          )
      end)

    inputs ++ outputs ++ rules
  end

  defp expression_entries(entries, model, names, path) do
    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, index} -> expression(entry, model, names, path ++ [index]) end)
  end

  defp text_entries(entries, grammar, model, names, path) do
    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn {text, index} -> syntax(text, grammar, model, names, path ++ [index]) end)
  end

  defp item_tests(item, model, names, path) do
    tests =
      if feel_language?(model, nil),
        do: syntax(item.allowed_values, :unary_tests, model, names, path ++ [:allowed_values]),
        else: []

    tests ++
      (item.components
       |> Enum.with_index()
       |> Enum.flat_map(fn {component, index} ->
         item_tests(component, model, names, path ++ [:components, component.id || index])
       end))
  end

  defp syntax(nil, _grammar, _model, _names, _path), do: []

  defp syntax(text, grammar, _model, names, path),
    do: [%{text: text, grammar: grammar, names: names, path: path}]

  defp validate_position(
         %{text: text, grammar: grammar, names: names, path: path},
         model,
         profile
       ) do
    normalized = FEEL.normalize_expression(text, names)

    result =
      if profile == :wedge_v1 do
        Boxic.FEEL.Profile.validate(normalized, grammar)
      else
        case grammar do
          :expression -> Boxic.FEEL.parse(normalized)
          :unary_tests -> Boxic.FEEL.validate_unary_tests(normalized)
        end
      end

    case result do
      :ok ->
        []

      {:ok, _ast} ->
        []

      {:error, error} ->
        [
          %Diagnostic{
            code:
              if(error.code == :unsupported_profile,
                do: :unsupported_profile,
                else: :invalid_feel_syntax
              ),
            category: :feel,
            path: path,
            message: "FEEL #{grammar}: #{error.message}",
            specification:
              if(error.code == :unsupported_profile,
                do: "Boxic wedge_v1 library policy",
                else: "DMN 1.5"
              ),
            clause: if(error.code == :unsupported_profile, do: nil, else: "10.3.1.2"),
            source_profile: model.source_profile,
            cause: error,
            details: %{grammar: grammar, text: text}
          }
        ]
    end
  end

  defp feel_language?(model, local_declaration) do
    match?(
      {:ok, _language},
      Compatibility.expression_language(
        model.source_profile,
        model.definitions.expression_language,
        local_declaration
      )
    )
  end

  defp variable_names(nil, _model), do: []

  defp variable_names(variable, model) do
    [variable.name | type_names(variable.type_ref, model, [])]
  end

  # Context keys become visible when a boxed filter/iterator binds a result,
  # or a previous context entry supplies one. Inspect declarations/AST only.
  defp result_names(%ContextExpression{entries: entries}, model) do
    case List.last(entries) do
      %{variable: nil, expression: expression} -> result_names(expression, model)
      _ -> Enum.flat_map(entries, &variable_names(&1.variable, model))
    end
  end

  defp result_names(%ListExpression{items: items}, model),
    do: Enum.flat_map(items, &result_names(&1, model))

  defp result_names(%Relation{columns: columns}, model),
    do: Enum.flat_map(columns, &variable_names(&1, model))

  defp result_names(%LiteralExpression{text: text} = literal, model) when is_binary(text) do
    keys =
      case Boxic.FEEL.parse(text) do
        {:ok, ast} -> context_keys(ast)
        {:error, _error} -> []
      end

    keys ++ type_names(literal.type_ref, model, [])
  end

  defp result_names(_expression, _model), do: []

  defp context_keys({:context, entries}),
    do: Enum.flat_map(entries, fn {name, ast} -> [name | context_keys(ast)] end)

  defp context_keys(ast) when is_tuple(ast),
    do: ast |> Tuple.to_list() |> Enum.flat_map(&context_keys/1)

  defp context_keys(asts) when is_list(asts), do: Enum.flat_map(asts, &context_keys/1)
  defp context_keys(_ast), do: []

  defp type_names(nil, _model, _seen), do: []

  defp type_names(type_ref, model, seen) do
    if type_ref in seen do
      []
    else
      case Map.get(model.item_definitions, type_ref) do
        nil -> []
        item -> component_names(item, model, [type_ref | seen])
      end
    end
  end

  defp component_names(item, model, seen) do
    type_names(item.type_ref, model, seen) ++
      Enum.flat_map(item.components, fn component ->
        [component.name | component_names(component, model, seen)]
      end)
  end
end
