# Opt-in evaluation tracing design

Review base: accepted XML-editing commit `83032a0`. This proposal is recorded
before implementation against that evaluator, not inferred from a different DMN
engine. No arithmetic, hit-policy or execution-budget changes are included.

## Public API and failure contract

```elixir
Boxic.DMN.evaluate_with_trace(model, "Decision", inputs)
Boxic.DMN.evaluate_with_trace(model, "Decision", inputs, external_functions: registry)
Boxic.DMN.evaluate_service_with_trace(model, "Service", arguments, opts)
# => {:ok, value, %Boxic.DMN.Trace{}}
# => {:error, original_reason, %Boxic.DMN.Trace{}}
```

The decision form defaults inputs to `%{}` and options to `[]`; the service form
requires arguments and defaults options to `[]`. Existing evaluate/service APIs,
return shapes, options and evaluation order are unchanged. Trace APIs return the
same value or tagged error plus evidence accumulated during that one execution.
Preflight, coercion and lookup failures return an empty/partial trace with the
original error. Exceptions, throws and exits that ordinary evaluation propagates
still propagate; this API does not promise a returned trace after a process dies.
Existing host-boundary error redaction remains in force. No broad rescue converts
programming errors into new evaluation results.

## Trace structure

The version-1 `Trace` struct contains `version`, `entrypoint`, `status`, `result`,
`error`, `stage`, `events`, and `truncated: false`. Result/error values are original
BEAM/FEEL terms, including Decimal; this is not a JSON serialization contract. Values
can include sensitive business data or callable terms. No storage or logging is
performed by the engine.

Events are ordered by start, each with an invocation-local `event_id`, `parent_id`,
`kind`, and `status`. IDs of events identify this execution only. Source identifiers
use `source_id`, remaining nil if absent; loader-generated decision lookup keys
are exposed separately as `lookup_key`, not passed off as source IDs. Table, rule
and cell positions are zero-based. Anonymous expression events have invocation-local
parent/start order rather than a promised stable source locator. Repeated invocations
get separate events even when they share a source ID.

- Decision events include name/key, result/error and `execution` (`:evaluated` or
  `:memoized`). Dependency events include kind, reference, position, resolved
  target and resolution (`:provided`, `:evaluated`, `:memoized`, or `:bound` for a
  callable). A provided dependency is not falsely called an evaluated decision.
- Expression events describe visited normalized boxed/literal expression
  boundaries. Parent relationships cover nested expressions, BKM calls and
  decision-service calls. A deliberately unselected boxed branch is recorded as
  `:not_evaluated`; its descendants are not speculatively traversed. FEEL AST
  internals are outside this trace's scope. Boxed filter/iterator events count
  entered and remaining iterations, including quantifier short circuits, without
  evaluating skipped bodies. A boxed invocation includes its resolved BKM reference.
- Table events contain table source ID, hit policy/aggregation, ordered input
  cells and their actual values/errors, ordered rules, rule condition and output
  cells, matched rule references, contributing rule references, default cells,
  outcome and final result/error. Rule references contain source ID and position.
  A value of nil is distinguished from work not performed by status.
- Rule matching is `:matched`, `:not_matched`, `:error`, or `:not_evaluated`.
  Cells retain `:ok`, `:error`, or `:not_evaluated`, and reasons for skipped work
  where known. Unmatched rule outputs are not evaluated; later conditions after
  a false/error condition and later rules/outputs after failure remain explicitly
  unevaluated. Failure never implies that all possible matches were determined.
- Contributions are nil until successful hit-policy selection and `[]` on a
  completed no-match/default path. Rule/default outputs completed before a failure
  remain available. Top-level and enclosing decision/table errors retain partial
  child evidence. Unrelated decisions absent from the visited event tree are not
  claimed to have run.

If an existing host boundary catches an exception raised inside a BKM, the
outer evaluation can return a tagged error while nested events survive. Those
attempted operations/cells use `:interrupted` when no tagged return was observed;
they are not labeled `:not_evaluated`, and no exception text bypasses the existing
host redaction. Truly propagated exceptions still return no trace.

Input/default cell source IDs identify their owning input/output clauses. The
normalized model does not retain source IDs for every rule cell, so those cells
use positions rather than fabricated IDs. Expression events without IDs use
invocation-local parentage/start order, not a stable source edit locator.

## Actual hit-policy behavior to preserve

The current evaluator evaluates table inputs, scans **all** rule conditions, then
evaluates **all** matched rule outputs, before reducing the hit policy. FIRST
therefore reports all actually matched/evaluated rules, with only the first
contributing. It must not be changed to short-circuit for tracing.

UNIQUE contributes its sole rule; ANY contributes all agreeing matches; FIRST
contributes the first; PRIORITY contributes the first ranked rule; RULE_ORDER and
OUTPUT_ORDER contribute all rules in result order. COLLECT (including SUM, MIN,
MAX and COUNT) reports all consumed matching rules as contributors: this means
aggregation operands, not only extrema. On a hit-policy error, contributions
remain undetermined (nil). Priority ordering reuses the ranks computed during
ordinary reduction, never a second evaluation of output priorities.

Defaults are evaluated only on the existing no-result path for UNIQUE, FIRST,
ANY, PRIORITY and COLLECT, and only when all output defaults are text. Otherwise
those paths return nil, including empty COLLECT/COUNT as currently implemented.
RULE_ORDER's empty result is a list; OUTPUT_ORDER still performs its existing
priority validation. The trace distinguishes `:matched`, `:default`, `:no_match`
and incomplete/error outcomes without changing any of these semantics.

## Implementation boundary and size

One scoped, synchronous process-local collector records events around the real
evaluator operations. This avoids changing FEEL callback return contracts or
threading a mutable trace through captured BKM/function/service closures. It is
not an alternate execution engine. Ordinary entry points suspend an enclosing
collector; nested trace entry points use independent scopes. `try/after` restores
previous state on success, tagged failure, exception or throw. No model input can
enable tracing. Concurrent processes have separate collectors; work in a host
function's spawned process is outside this synchronous trace.

When tracing is disabled, event builders and cell inventories should not be
constructed. No expressions are re-evaluated, and no skipped branch, host call or
priority expression runs for evidence. Optional capture retains all recorded
values/events with **no truncation or new execution limit**. Memory grows with
actual invocations and table cells, plus retained value sizes; repeated BKM and
iterator calls can make traces large. Event parentage and table inventories
identify pending work without building a speculative full model execution tree.
