# Boxic DMN

Boxic DMN is a native Elixir loader, validator, and evaluator for Decision
Model and Notation (DMN) 1.5 models. It uses `boxic_feel` for expression
evaluation and does not require a JVM.

## Installation

Add `boxic_dmn` to `mix.exs`:

```elixir
def deps do
  [
    {:boxic_dmn, "~> 0.2.0"}
  ]
end
```

## Quick start

Load XML explicitly, validate its normalized model, and evaluate a decision:

```elixir
xml = """
<definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
  id="example" name="Example" namespace="https://example.com/boxic">
  <decision id="greeting" name="Greeting">
    <literalExpression>
      <text>"Hello " + name</text>
    </literalExpression>
  </decision>
</definitions>
"""

with {:ok, model} <- Boxic.DMN.load_xml(xml),
     :ok <- Boxic.DMN.validate(model, for: :evaluation),
     {:ok, greeting} <- Boxic.DMN.evaluate(model, "Greeting", %{"name" => "Ada"}) do
  greeting
end
```

Use `Boxic.DMN.load_file/1` for a filesystem path. It resolves only declared
relative `locationURI` imports below the root model directory. In-memory XML
has no ambient authority; pass an `imports:` map or `resolver:` to
`load_xml/2`. The compatibility `Boxic.DMN.load/1` function accepts either
XML-looking input or a path, but new code should use the explicit functions.

Loading returns `{:ok, %Boxic.DMN.Model{}}` or a documented load error.
Capability validation returns `:ok` or stable `Boxic.DMN.Diagnostic` values:

Evaluation and authoring validation parse every supported FEEL expression and
unary-test position, including unused decisions, nested branches, table outputs,
defaults and allowed values. No business inputs or evaluation are required.
Malformed supported syntax produces positioned `:invalid_feel_syntax` diagnostics.
Syntax success does not guarantee runtime success. Structural `validate/1`, XML
loading, serialization checks and ordinary evaluation retain their existing behavior.

```elixir
Boxic.DMN.validate(model, for: :evaluation)
Boxic.DMN.validate(model, for: :serialization)
Boxic.DMN.validate(model, for: :authoring)
```

Use `inspect_xml/1` for a best-effort view of older or unsupported documents;
inspection does not grant executable or writable status.

## Trace an evaluation

Decision, service and traced evaluation use FEEL's scoped 34-digit, half-even
Decimal context, including COLLECT aggregation, and restore the caller's full
context after success or failure. Explicit rounding functions and no-match
COLLECT/default behavior are unchanged. See [the arithmetic contract](../../docs/scoped-feel-arithmetic.md)
for numeric-failure handling and the separate numeric-admission audit boundary.

`Boxic.DMN.evaluate_with_trace/4` and `evaluate_service_with_trace/4` return
`{:ok, value, trace}` or `{:error, original_reason, trace}` from one execution.
The ordinary evaluation APIs keep their existing two-element return shapes.

```elixir
{:ok, value, trace} = Boxic.DMN.evaluate_with_trace(model, "Price", inputs)
tables = Enum.filter(trace.events, &(&1.kind == :table))
```

Traces include decision dependencies, actual table inputs, rule conditions and
outputs, matched versus contributing rules, defaults and partial tagged failures.
Source IDs remain nil when absent; table/rule/cell positions are zero-based.
They reflect existing evaluation order, including all matched outputs evaluated
before FIRST reduction. Values remain native terms and are retained without
truncation; trace size grows with work and value size. Exceptions still propagate.
See [the trace contract](../../docs/evaluation-tracing.md) for scope, contribution
definitions, process isolation and limitations. No trace is logged or persisted.

## Edit and export decision tables

`Boxic.DMN.Authoring.DecisionTable` provides immutable, ID-based operations for
the structural edits a decision-table UI commonly performs. For example:

```elixir
alias Boxic.DMN.Authoring.DecisionTable, as: Authoring

with {:ok, model} <- Boxic.DMN.load_xml(xml),
     {:ok, model} <-
       Authoring.put_input_entry(model,
         decision_id: "eligibility",
         rule_id: "adult",
         input_id: "customer_age",
         text: ">= 18"
       ),
     :ok <- Boxic.DMN.validate(model),
     {:ok, written_xml} <- Boxic.DMN.encode_xml(model) do
  written_xml
end
```

Adding, removing, or moving an input or output clause updates the corresponding
entry position in every rule. The caller provides stable IDs; Boxic does not
generate random identifiers. UI-only draft, selection, undo, and persistence
state remains an application concern.

For a bounded edit to original XML that the normalized writer cannot retain,
use `edit_xml/3`:

```elixir
{:ok, revised_xml} = Boxic.DMN.edit_xml(original_xml, %{
  table_id: "eligibility_table", rule_id: "adult", input_id: "age_input", text: ">= 21"
})
```

It accepts one existing expression ID, a direct literal's decision ID, or table,
rule and clause IDs. Surrounding admitted XML content is preserved semantically,
including descriptions, annotations, namespaces and diagrams. Unknown XML names,
processing instructions and unsupported edits are refused explicitly. The output
is strictly reloaded and syntax-validated without executing business expressions.
This is not arbitrary-model editing or byte-for-byte preservation; it does not
make a lossy normalized Model writable. See `edit_xml/3` documentation for request
forms and the repository's `docs/xml-preserving-edits.md` for the exact boundary.

`encode_xml/2` emits deterministic DMN 1.5 XML. Its options are:

```elixir
[format: :pretty | :compact, xml_declaration: true | false]
```

The defaults are pretty two-space output with an XML declaration, LF line
endings, and one final newline. `Boxic.DMN.validate_serializable/2` performs the
same preflight checks without producing XML.

The writer guarantees semantic rather than byte-identical source
round-tripping. A loaded model is rejected when its DMN version differs from
the pinned output version or when the loader detected content it could not
retain, such as unsupported extensions or DMNDI. This prevents an edit/export
workflow from silently discarding authored content.

Focused writer performance can be measured without adding work to the ordinary
test suite:

```console
mix run bench/xml_writer_bench.exs
```

The benchmark covers 100, 1,000, and 10,000-rule tables and reports elapsed
time, output size, and process memory.

Maintainers building or publishing this umbrella child as a Hex package must
select the published `boxic_feel` dependency rather than the local sibling:

```console
BOXIC_DMN_HEX_BUILD=true mix hex.build
BOXIC_DMN_HEX_BUILD=true mix hex.publish
```

## Compatibility

Boxic targets DMN 1.5. Against the vendored official DMN Technology
Compatibility Kit revision `a162739daee85fb28e9d3bec2f306505992dae0f`, the
DMN suite passes all 1,485 selected cases. This result covers the DMN suite;
the separate FEEL suite is reported by `boxic_feel`.

Evaluator results, strict schema loading, imports, and native writer round
trips are recorded as independent evidence. TCK models containing unmodeled
extensions or DMNDI remain explicitly non-writable; they are never silently
converted or presented as complete interchange coverage.

See [CONFORMANCE.md](CONFORMANCE.md) for the public boundary and
[CONSTRUCT_CAPABILITY_LEDGER.md](CONSTRUCT_CAPABILITY_LEDGER.md) for the exact
modeled, executable, writable, and blocked construct surface.

Java external-function integration is intentionally not implemented because
Boxic runs on the BEAM rather than the JVM. Trusted host functions can instead
be exposed through `Boxic.FEEL.ExternalFunctions`.

## External functions and trust

Pass an allowlisted external-function registry when evaluating:

```elixir
Boxic.DMN.evaluate(model, "Price", inputs,
  external_functions: MyApp.DecisionFunctions
)

Boxic.DMN.evaluate_service(model, "Pricing Service", arguments,
  external_functions: MyApp.DecisionFunctions
)
```

Registry entries execute application code in the evaluator process. Construct
registries only from trusted application configuration, never from model
content or untrusted strings. The registry is kept outside ordinary FEEL
context data. Built-ins win collisions unless the host explicitly passes
`external_function_precedence: :registered`. Applications should isolate or
time-limit functions that perform remote or long-running work.

## License

Boxic DMN is licensed under Apache-2.0. The official TCK corpus and local
compatibility artifacts are not included in the Hex package.

### Opt-in bounded v1 evaluation

The `:bounded_v1` capability is a conservative library profile. Before accepting a
model, use `Boxic.DMN.validate(model, for: :evaluation, profile: :bounded_v1)`.
Use `profile: :bounded_v1` on ordinary/traced evaluation to enforce the same gate.
The profile checks all supported expression/test positions and unused branches.
It excludes exp/log, dynamic calls, FEEL function definitions, callback-taking
sort/list-replace, BKMs, imports and boxed invocation/functions. Powers require a
literal integer exponent with magnitude at most 1024. Callable inputs and external
function registries are rejected. Legacy evaluation is still available and does
not imply qualification under this profile.

```elixir
Boxic.DMN.evaluate_bounded(model, "Price", inputs,
  timeout: 1000, max_heap_words: 8_000_000,
  trace: true, trace_max_bytes: 1_000_000)
# {:ok, {:ok, value, trace}}, {:ok, {:error, error, trace}},
# or {:error, boundary_error}
```

`evaluate_service_bounded/4` has the same contract. The monitored worker executes
once and enforces the v1 gate. Deadline/worker termination errors cannot return a
completed trace. `Boxic.FEEL.Execution` describes boundary errors. Caller death
kills the worker; late monitor messages do not escape a completed call.

`:trace_max_bytes` on ordinary traced APIs defaults to `:infinity`; bounded APIs
default to 1 MB and require a finite budget. The budget measures retained event
external-term size, not an exact heap ceiling or final result size. Exhaustion
freezes evidence with `truncated: true, truncation_reason: :event_size_limit`;
results and scheduling remain unchanged. Retained unfinished events are incomplete,
not proof that work was skipped. Metadata/update construction may temporarily
exceed the retained budget. The empty event container has constant overhead.

The heap limit is checked at GC and accounts for shared binaries; it is not an
instantaneous cap, NIF deadline guarantee, descendant limit or OS sandbox. Caller
input/result quotas, concurrency, supervision and stronger isolation remain caller
responsibilities. No process dictionary is inherited by the worker. Numeric
execution always establishes its own scoped arithmetic context.

`validate_xml_schema(xml, timeout: 5000)` bounds the native validator. Its resource
owner monitors caller death, kills the directly owned xmllint process, closes the
Port and removes its exclusively created temporary file. Output is capped at
4000 bytes; existing 5 MB XML, node/depth/DTD/name protections remain. Native
termination/reaping may add cleanup latency beyond the requested deadline.
POSIX `kill` and xmllint are required; the library does not promise cleanup after
VM/OS termination or kill arbitrary native descendant trees.
