defmodule Boxic.DMN.DecisionTable do
  @moduledoc false
  alias Boxic.DMN.{FEEL, Trace}
  alias Boxic.DMN.Model.DecisionTable

  def evaluate(%DecisionTable{} = table, context) do
    Trace.table(table, fn ->
      with :ok <- Trace.table_phase(:inputs),
           {:ok, input_values} <- evaluate_table_inputs(table.inputs, context),
           :ok <- Trace.table_phase(:matching),
           {:ok, matches} <- matching_rules(table.rules, input_values, context),
           :ok <- Trace.table_phase(:outputs),
           {:ok, results} <- evaluate_matched_outputs(matches, table.outputs, context),
           :ok <- Trace.table_phase(:hit_policy),
           {:ok, value} <-
             reduce_hit_policy(table, Enum.map(matches, &elem(&1, 0)), results, context) do
        Trace.contributing(table.hit_policy)
        {:ok, value}
      end
    end)
  end

  defp evaluate_matched_outputs(rules, outputs, context) do
    Enum.reduce_while(rules, {:ok, []}, fn {rule, index}, {:ok, values} ->
      Trace.rule_output(index, :started)
      result = evaluate_rule_outputs(rule, outputs, context, index)
      Trace.rule_output(index, result)

      case result do
        {:ok, value} -> {:cont, {:ok, values ++ [value]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp reduce_hit_policy(table, _rules, [], context)
       when table.hit_policy in ~w(UNIQUE FIRST ANY PRIORITY COLLECT),
       do: evaluate_default_outputs(table.outputs, context)

  defp reduce_hit_policy(%DecisionTable{hit_policy: "UNIQUE"}, rules, results, _context) do
    case results do
      [result] -> {:ok, result}
      _ -> {:error, {:unique_hit_policy_violation, Enum.map(rules, & &1.id)}}
    end
  end

  defp reduce_hit_policy(%DecisionTable{hit_policy: "FIRST"}, _rules, [result | _], _context),
    do: {:ok, result}

  defp reduce_hit_policy(%DecisionTable{hit_policy: "ANY"}, rules, [result | rest], _context) do
    if Enum.all?(rest, &(&1 == result)),
      do: {:ok, result},
      else: {:error, {:any_hit_policy_violation, Enum.map(rules, & &1.id)}}
  end

  defp reduce_hit_policy(%DecisionTable{hit_policy: "RULE_ORDER"}, _rules, results, _context),
    do: {:ok, results}

  defp reduce_hit_policy(
         %DecisionTable{hit_policy: "COLLECT", aggregation: nil},
         _rules,
         results,
         _context
       ),
       do: {:ok, results}

  defp reduce_hit_policy(
         %DecisionTable{hit_policy: "COLLECT", aggregation: aggregation},
         _rules,
         results,
         _context
       ),
       do: aggregate_collect(aggregation, results)

  defp reduce_hit_policy(%DecisionTable{hit_policy: policy} = table, _rules, results, context)
       when policy in ~w(PRIORITY OUTPUT_ORDER) do
    with {:ok, ordered} <- order_by_priority(table, results, context) do
      if policy == "PRIORITY", do: {:ok, List.first(ordered)}, else: {:ok, ordered}
    end
  end

  defp aggregate_collect("COUNT", results), do: {:ok, Decimal.new(length(results))}
  defp aggregate_collect(_aggregation, []), do: {:ok, nil}

  defp aggregate_collect("SUM", results) do
    if Enum.all?(results, &match?(%Decimal{}, &1)),
      do: {:ok, Enum.reduce(results, Decimal.new(0), &Decimal.add/2)},
      else: {:error, :collect_aggregation_requires_numbers}
  end

  defp aggregate_collect(aggregation, results) when aggregation in ~w(MIN MAX) do
    if Enum.all?(results, &match?(%Decimal{}, &1)) do
      chooser =
        case aggregation do
          "MIN" ->
            fn value, current ->
              if Decimal.compare(value, current) == :lt, do: value, else: current
            end

          "MAX" ->
            fn value, current ->
              if Decimal.compare(value, current) == :gt, do: value, else: current
            end
        end

      {:ok, Enum.reduce(results, chooser)}
    else
      {:error, :collect_aggregation_requires_numbers}
    end
  end

  defp order_by_priority(%DecisionTable{outputs: [priority_output | _]}, results, context) do
    with values when is_binary(values) <- priority_output.allowed_values,
         {:ok, priorities} <- evaluate_priority_values(values, context),
         ranked <- Enum.map(results, &rank_result(&1, priority_output, priorities)),
         true <- Enum.all?(ranked, &match?({rank, _} when is_integer(rank), &1)) do
      ordered =
        ranked |> Enum.with_index() |> Enum.sort_by(fn {{rank, _value}, _index} -> rank end)

      Trace.priority_order(Enum.map(ordered, &elem(&1, 1)))
      {:ok, Enum.map(ordered, fn {{_rank, value}, _index} -> value end)}
    else
      nil -> {:error, :missing_output_priorities}
      false -> {:error, :output_not_in_priority_values}
      {:error, _reason} = error -> error
    end
  end

  defp evaluate_priority_values(values, context) do
    {expression, bindings} = FEEL.normalize_names("[#{values}]", context)

    case Boxic.FEEL.evaluate(expression, bindings) do
      {:ok, priorities} when is_list(priorities) -> {:ok, priorities}
      {:ok, _value} -> {:error, :invalid_output_priorities}
      error -> error
    end
  end

  defp rank_result(result, output, priorities) do
    value =
      if is_map(result),
        do: Map.get(result, output.name || output.label),
        else: result

    {Enum.find_index(priorities, &(&1 == value)), result}
  end

  defp evaluate_table_inputs(inputs, context) do
    inputs
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {input, index}, {:ok, values} ->
      {expression, bindings} = FEEL.normalize_names(input.expression, context)

      Trace.table_cell(:inputs, index, :started)
      result = Boxic.FEEL.evaluate(expression, bindings)
      Trace.table_cell(:inputs, index, result)

      case result do
        {:ok, value} -> {:cont, {:ok, values ++ [value]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp matching_rules(rules, input_values, context) do
    rules
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {rule, index}, {:ok, matches} ->
      Trace.rule_match(index, :started)
      result = rule_matches?(rule, input_values, context, index)
      Trace.rule_match(index, result)

      case result do
        {:ok, true} -> {:cont, {:ok, matches ++ [{rule, index}]}}
        {:ok, false} -> {:cont, {:ok, matches}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp rule_matches?(rule, input_values, context, rule_index) do
    Enum.zip(rule.input_entries, input_values)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, true}, fn {{test, value}, index}, {:ok, true} ->
      Trace.rule_cell(rule_index, :conditions, index, :started)
      result = evaluate_unary_tests(test, value, context)
      Trace.rule_cell(rule_index, :conditions, index, result)

      case result do
        {:ok, true} -> {:cont, {:ok, true}}
        {:ok, false} -> {:halt, {:ok, false}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp evaluate_unary_tests(text, value, context) do
    {text, context} = FEEL.normalize_names(text, context)

    text
    |> split_unary_tests()
    |> Enum.reduce_while({:ok, false}, fn test, {:ok, false} ->
      case Boxic.FEEL.evaluate_unary_test(test, value, context) do
        {:ok, true} -> {:halt, {:ok, true}}
        {:ok, false} -> {:cont, {:ok, false}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp split_unary_tests(text) do
    Regex.split(~r/,(?=(?:[^"]*"[^"]*")*[^"]*$)/, text, trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp evaluate_rule_outputs(rule, outputs, context, rule_index) do
    with {:ok, values} <-
           evaluate_output_entries(rule.output_entries, context, {:rule, rule_index}) do
      shape_output(outputs, values)
    end
  end

  defp evaluate_default_outputs(outputs, context) do
    defaults = Enum.map(outputs, & &1.default_output)

    if Enum.all?(defaults, &is_binary/1) do
      Trace.table_phase(:defaults)
      Trace.default_outcome(:default)

      with {:ok, values} <- evaluate_output_entries(defaults, context, :defaults),
           do: shape_output(outputs, values)
    else
      Trace.default_outcome(:no_match)
      {:ok, nil}
    end
  end

  defp evaluate_output_entries(entries, context, position) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {expression, index}, {:ok, values} ->
      {expression, bindings} = FEEL.normalize_names(expression, context)

      Trace.output_cell(position, index, :started)
      result = Boxic.FEEL.evaluate(expression, bindings)
      Trace.output_cell(position, index, result)

      case result do
        {:ok, value} -> {:cont, {:ok, values ++ [value]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp shape_output([_output], [value]), do: {:ok, value}

  defp shape_output(outputs, values) do
    names = Enum.map(outputs, &(&1.name || &1.label))

    if Enum.all?(names, &is_binary/1),
      do: {:ok, names |> Enum.zip(values) |> Map.new()},
      else: {:error, :unnamed_multiple_outputs}
  end

  # FEEL names may contain spaces and reserved words. The dependency graph gives
  # us the exact declared names, so compile those names to unambiguous evaluator
  # bindings before parsing the literal expression.
end
