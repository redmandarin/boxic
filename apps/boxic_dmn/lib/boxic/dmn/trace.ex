defmodule Boxic.DMN.Trace do
  @moduledoc """
  Evidence collected during one synchronous DMN evaluation.

  Events are ordered by start and linked by invocation-local `event_id` and
  `parent_id`. `source_id` is nil when absent; positions are zero-based.
  Values and errors remain native terms, including Decimal and callable values.
  No redaction, logging or persistence is performed. Optional `:trace_max_bytes`
  caps the external-term size of retained events (not the final result). On
  exhaustion collection freezes and `truncated` is true; unfinished events remain
  interrupted. Evaluation continues once with unchanged scheduling and results.
  Metadata construction and a single update can temporarily exceed the retained
  budget. Use the worker heap boundary and caller input/result quotas as well.
  """

  defstruct version: 1,
            entrypoint: nil,
            status: nil,
            stage: nil,
            result: nil,
            error: nil,
            events: [],
            truncated: false,
            truncation_reason: nil

  @type t :: %__MODULE__{
          version: 1,
          entrypoint: map(),
          status: :ok | :error,
          stage: atom(),
          result: term(),
          error: term(),
          events: [map()],
          truncated: boolean(),
          truncation_reason: nil | :event_size_limit
        }

  @collector_key {__MODULE__, :collector}

  @doc false
  def capture(model, entrypoint, callback, opts \\ []) do
    maximum = Keyword.get(opts, :trace_max_bytes, :infinity)

    if maximum == :infinity or (is_integer(maximum) and maximum >= 0) do
      capture_events(model, entrypoint, callback, maximum)
    else
      error =
        Boxic.FEEL.Error.new(
          :invalid_option,
          "trace_max_bytes must be a nonnegative integer or :infinity"
        )

      {:error, error,
       %__MODULE__{entrypoint: entrypoint, status: :error, stage: :options, error: error}}
    end
  end

  defp capture_events(model, entrypoint, callback, maximum) do
    previous = Process.get(@collector_key)

    generated =
      for {:missing_id, kind, id} <- model.issues, do: {Macro.camelize(Atom.to_string(kind)), id}

    Process.put(@collector_key, %{
      next: 1,
      stack: [],
      events: %{},
      stage: :options,
      generated: generated,
      maximum: maximum,
      truncated: false
    })

    try do
      result = callback.()
      state = Process.get(@collector_key)
      events = state.events |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))

      trace = %__MODULE__{
        entrypoint: entrypoint,
        stage: state.stage,
        events: events,
        truncated: state.truncated,
        truncation_reason: if(state.truncated, do: :event_size_limit, else: nil)
      }

      case result do
        {:ok, value} -> {:ok, value, %{trace | status: :ok, result: value}}
        {:error, error} -> {:error, error, %{trace | status: :error, error: error}}
      end
    after
      restore(previous)
    end
  end

  @doc false
  def without_capture(callback) do
    previous = Process.get(@collector_key)
    Process.delete(@collector_key)

    try do
      callback.()
    after
      restore(previous)
    end
  end

  defp restore(nil), do: Process.delete(@collector_key)
  defp restore(previous), do: Process.put(@collector_key, previous)

  @doc false
  def stage(stage) do
    update(fn state -> %{state | stage: stage} end)
    :ok
  end

  @doc false
  def span(kind, metadata, callback) do
    case Process.get(@collector_key) do
      nil ->
        callback.()

      %{truncated: true} ->
        callback.()

      state ->
        id = state.next

        event =
          Map.merge(metadata.(), %{
            event_id: id,
            parent_id: List.first(state.stack),
            kind: kind,
            status: :interrupted
          })

        retained =
          retain(state, %{
            state
            | next: id + 1,
              stack: [id | state.stack],
              events: Map.put(state.events, id, event)
          })

        if retained do
          try do
            result = callback.()
            annotate(completion(kind, result))
            result
          after
            update(fn current -> %{current | stack: state.stack} end)
          end
        else
          callback.()
        end
    end
  end

  defp completion(:dependency, {:ok, _context, _memo}), do: %{status: :ok}
  defp completion(_kind, {:ok, value, _memo}), do: %{status: :ok, result: value}
  defp completion(_kind, {:ok, value}), do: %{status: :ok, result: value}
  defp completion(:table, {:error, error}), do: %{status: :error, error: error, outcome: :error}
  defp completion(_kind, {:error, error}), do: %{status: :error, error: error}

  @doc false
  def annotate(fields) do
    update(fn state ->
      case state.stack do
        [id | _] -> %{state | events: Map.update!(state.events, id, &Map.merge(&1, fields))}
        [] -> state
      end
    end)
  end

  @doc false
  def collection(source) do
    update(fn state ->
      [id | _] = state.stack

      fields = %{
        iterations_total: length(source),
        iterations_evaluated: 0,
        iterations_not_evaluated: length(source)
      }

      %{state | events: Map.update!(state.events, id, &Map.merge(&1, fields))}
    end)
  end

  @doc false
  def iteration(index) do
    update(fn state ->
      [id | _] = state.stack

      %{
        state
        | events:
            Map.update!(state.events, id, fn event ->
              Map.merge(event, %{
                iterations_evaluated: index + 1,
                iterations_not_evaluated: event.iterations_total - index - 1
              })
            end)
      }
    end)
  end

  @doc false
  def node(node) do
    kind = node.__struct__ |> Module.split() |> List.last()

    generated =
      case Process.get(@collector_key) do
        nil -> []
        state -> state.generated
      end

    %{
      source_id: if({kind, node.id} in generated, do: nil, else: node.id),
      lookup_key: node.id,
      name: Map.get(node, :name)
    }
  end

  @doc false
  def expression(expression, callback) do
    span(:expression, fn -> expression_reference(expression) end, callback)
  end

  defp expression_reference(nil), do: %{source_id: nil, expression_kind: :missing}
  defp expression_reference({:unsupported, kind}), do: %{source_id: nil, expression_kind: kind}

  defp expression_reference(expression),
    do: %{
      source_id: expression.id,
      expression_kind: expression.__struct__ |> Module.split() |> List.last()
    }

  @doc false
  def skipped(expression, position, reason) do
    case Process.get(@collector_key) do
      nil ->
        :ok

      _state ->
        span(
          :expression,
          fn ->
            Map.merge(expression_reference(expression), %{position: position, reason: reason})
          end,
          fn -> {:ok, nil} end
        )

        update(fn state ->
          %{
            state
            | events:
                Map.update!(
                  state.events,
                  state.next - 1,
                  &(&1 |> Map.put(:status, :not_evaluated) |> Map.delete(:result))
                )
          }
        end)
    end
  end

  @doc false
  def table(table, callback) do
    span(
      :table,
      fn ->
        %{
          source_id: table.id,
          hit_policy: table.hit_policy,
          aggregation: table.aggregation,
          inputs: cells(table.inputs, & &1.expression),
          rules:
            table.rules
            |> Enum.with_index()
            |> Enum.map(fn {rule, index} ->
              %{
                source_id: rule.id,
                position: index,
                status: :not_evaluated,
                output_status: :not_evaluated,
                conditions: text_cells(rule.input_entries),
                outputs: text_cells(rule.output_entries)
              }
            end),
          defaults: cells(table.outputs, & &1.default_output),
          matched_rules: [],
          contributing_rules: nil,
          outcome: :not_completed
        }
      end,
      callback
    )
  end

  defp cells(items, text) do
    items
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      %{source_id: item.id, position: index, text: text.(item), status: :not_evaluated}
    end)
  end

  defp text_cells(texts),
    do:
      texts
      |> Enum.with_index()
      |> Enum.map(fn {text, index} -> %{position: index, text: text, status: :not_evaluated} end)

  @doc false
  def table_cell(section, index, result) do
    update_table(fn table ->
      Map.update!(
        table,
        section,
        &List.update_at(&1, index, fn cell -> Map.merge(cell, cell_result(result)) end)
      )
    end)

    result
  end

  @doc false
  def output_cell(:defaults, index, result), do: table_cell(:defaults, index, result)

  def output_cell({:rule, rule_index}, index, result),
    do: rule_cell(rule_index, :outputs, index, result)

  @doc false
  def rule_cell(rule_index, section, cell_index, result) do
    update_table(fn table ->
      %{
        table
        | rules:
            List.update_at(table.rules, rule_index, fn rule ->
              Map.update!(
                rule,
                section,
                &List.update_at(&1, cell_index, fn cell ->
                  Map.merge(cell, cell_result(result))
                end)
              )
            end)
      }
    end)

    result
  end

  defp cell_result(:started), do: %{status: :interrupted}
  defp cell_result({:ok, value}), do: %{status: :ok, value: value}
  defp cell_result({:error, error}), do: %{status: :error, error: error}

  @doc false
  def rule_match(index, result) do
    update_table(fn table ->
      rule = Enum.at(table.rules, index)

      status =
        case result do
          :started -> :interrupted
          {:ok, true} -> :matched
          {:ok, false} -> :not_matched
          {:error, _} -> :error
        end

      rule = Map.put(rule, :status, status)

      rule =
        if status == :not_matched,
          do:
            Map.update!(
              rule,
              :outputs,
              &Enum.map(&1, fn cell -> Map.put(cell, :reason, :rule_not_matched) end)
            ),
          else: rule

      matches =
        if status == :matched,
          do: table.matched_rules ++ [Map.take(rule, [:source_id, :position])],
          else: table.matched_rules

      %{table | rules: List.replace_at(table.rules, index, rule), matched_rules: matches}
    end)

    result
  end

  @doc false
  def rule_output(index, result) do
    update_table(fn table ->
      %{table | rules: List.update_at(table.rules, index, &Map.merge(&1, output_result(result)))}
    end)

    result
  end

  defp output_result(:started), do: %{output_status: :interrupted}
  defp output_result({:ok, value}), do: %{output_status: :ok, result: value}
  defp output_result({:error, error}), do: %{output_status: :error, error: error}

  @doc false
  def table_phase(phase), do: update_table(&Map.put(&1, :phase, phase))

  @doc false
  def default_outcome(outcome), do: update_table(&Map.put(&1, :outcome, outcome))

  @doc false
  def priority_order(indices), do: update_table(&Map.put(&1, :priority_order, indices))

  @doc false
  def contributing(policy) do
    update_table(fn table ->
      matches = table.matched_rules

      rules =
        case policy do
          "FIRST" -> Enum.take(matches, 1)
          "PRIORITY" -> table |> ordered_matches(matches) |> Enum.take(1)
          "OUTPUT_ORDER" -> ordered_matches(table, matches)
          policy when policy in ["UNIQUE", "ANY", "RULE_ORDER", "COLLECT"] -> matches
        end

      outcome =
        if table.outcome == :not_completed,
          do: if(matches == [], do: :no_match, else: :matched),
          else: table.outcome

      Map.merge(table, %{contributing_rules: rules, outcome: outcome})
    end)
  end

  defp ordered_matches(table, matches),
    do: Enum.map(Map.get(table, :priority_order, []), &Enum.at(matches, &1))

  defp update_table(callback) do
    update(fn state ->
      case Enum.find(state.stack, &(state.events[&1].kind == :table)) do
        nil -> state
        id -> %{state | events: Map.update!(state.events, id, callback)}
      end
    end)
  end

  defp update(callback) do
    case Process.get(@collector_key) do
      nil ->
        :ok

      %{truncated: true} ->
        :ok

      state ->
        retain(state, callback.(state))
        :ok
    end
  end

  defp retain(previous, candidate) do
    if candidate.maximum == :infinity or
         :erlang.external_size(candidate.events) <= candidate.maximum do
      Process.put(@collector_key, candidate)
      true
    else
      Process.put(@collector_key, %{previous | truncated: true})
      false
    end
  end
end
