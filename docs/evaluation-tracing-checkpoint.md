# Evaluation-tracing review checkpoint

Review base: accepted XML-editing commit
`83032a0f568de74047742294f1ddaa53bf2f8f77`.
Branch: `improve/evaluation-traces`.

The [API/trace design](evaluation-tracing.md) was written against the actual
base evaluator before implementation. This checkpoint adds opt-in tracing only.
The ordinary decision/service APIs still return their existing two-element
results, and expressions run on the same evaluator path. No arithmetic,
hit-policy, XML-editing, dependency-pin or execution-limit correction is included.

The worktree remains `/private/tmp/boxic-xml-preserving-edits` with a new tracing
branch. Its pre-existing `_build`/`deps` symlinks are not committed. Instructions
were explicitly read from `/Users/pg/Documents/Code/projects/boxic/AGENTS.md`;
the untracked original file remains untouched. The projects checkout stays on
its existing branch. No push, publishing, PR creation or Wedge source edit occurred.

## Public contract

```elixir
{:ok, result, trace} = Boxic.DMN.evaluate_with_trace(model, "Decision", inputs)
{:ok, result, trace} = Boxic.DMN.evaluate_with_trace(model, "Decision", inputs,
  external_functions: registry)
{:ok, result, trace} = Boxic.DMN.evaluate_service_with_trace(model, "Service", args)
# Tagged failures return {:error, original_reason, trace}.
```

`Trace` version 1 retains native results/errors and a start-ordered tree of
invocation events linked by parent IDs. It includes visited decisions,
dependencies (provided/evaluated/memoized/bound), BKM/service calls, normalized
expression boundaries, actual table inputs/conditions/outputs, matched and
contributing rule references, defaults and no-match outcomes. Missing source IDs
remain nil. Rule/cell positions and invocation IDs are explicitly separate from
stable source IDs. The design documents the normalized-model limits on source
locations, including input/output clause ownership of cell references.

Rule inputs short circuit within a rule, but the base evaluator scans every rule
and evaluates every matched output before FIRST/PRIORITY reduction. Traces retain
that behavior. FIRST contributes the first match; PRIORITY contributes the first
ranked match. ANY lists agreeing matches as contributors; COLLECT aggregators list
all consumed matching operands (including MIN/MAX), not only extrema. Ordered
policies list contributions in result order. Contributions remain nil when no
successful selection/reduction was reached. This is an explicit trace definition,
not a claim to compute a minimal causal explanation.

Tagged failures preserve earlier cells, outputs and dependency evidence. A host
boundary may catch an exception from a BKM; cells entered without a returned
result then remain `:interrupted`, rather than falsely `:not_evaluated`.
Existing host redaction remains intact. Exceptions/throws/exits that ordinary
evaluation propagates still propagate, with no promise of a returned trace after
that failure. Cleanup is in `try/after`, with no production rescue translating
programming errors.

A scoped process-local collector is needed because FEEL's synchronous callback
contract returns results through BKM/function/service closures. It records the
actual operations without changing those callback contracts, inventing a second
evaluator or replaying expressions. Ordinary public entry points suspend an
outer collector; nested traced entry points use their own independent scope.
State is restored on both normal and exceptional returns. Concurrent processes
are isolated. Host-spawned processes are outside this synchronous trace.

Tracing retains all recorded values with `truncated: false`, with no new trace
budget. Memory grows with visits, table cell inventories and value sizes. There
is no JSON/serialization contract, logging or storage. This is not an arithmetic
AST debugger, complete speculative execution tree or resource sandbox. Inactive
hooks still perform collector checks; no performance benchmark is claimed.

## Verification

Runtime: Elixir 1.20.4 / OTP 28.5.0.8 on macOS ARM64. The repository's exact
Elixir 1.20.0 / OTP 29.0.1 pin is unavailable locally and remains a CI check.
The repository lock remains Decimal 3.1.1 / tz 0.28.2; the isolated Wedge harness
resolves its existing Decimal 3.2.0 / tz 0.28.4 pins. Package source/version
provenance remains as documented in [the baseline report](qualified-package-baseline.md):
upstream `8c1706f` executable/schema source matches Hex DMN 0.3.0 / FEEL 0.2.0,
while the source's release metadata differs and is unchanged here.

Commands were run with the installed runtime on PATH:

```sh
mix format --check-formatted
mix format --check-formatted scripts/verify_trace_tck.exs
mix compile --warnings-as-errors
mix test apps/boxic_dmn/test/evaluation_trace_test.exs
mix quality
mix test
MIX_ENV=test mix run --no-start scripts/verify_trace_tck.exs
mix tck --suite dmn --profile implemented
```

| Check | Result |
| --- | --- |
| Focused tracing regression tests | 41 passed |
| Full umbrella ExUnit suite | 216 passed: FEEL 36, DMN 157, TCK tooling 23 |
| Formatting, strict project compilation, strict Credo, Dialyzer | Passed without suppressions |
| Implemented FEEL TCK profile in root test alias | 2,042 passed; 18 known Java external-function exclusions |
| Implemented DMN TCK profile | 1,485 passed; no failed/error/missing/unsupported result |
| Exact traced/untraced TCK comparison | 1,485/1,485 result assertions agree across 69 models, including services |
| Wedge isolated engine suites | 26 passed, with two obsolete capability observations updated only in memory |
| Wedge native trace comparisons | Invoice `review` and refund `true` agree exactly |
| Wedge frozen selected-TCK trace comparison | 24 exact traced/untraced comparisons passed |
| Existing Wedge selected writer probes | 10 unsupported as before; fidelity refusal unchanged |

TCK revision: **`a162739daee85fb28e9d3bec2f306505992dae0f`**. The implemented
profiles are selected vendored suites, not full-current-upstream conformance or
certification. The new script compares tagged returns with strict BEAM equality,
not a numeric tolerance; propagated exceptions are compared by type/message and
throws/exits by reason, since trace instrumentation necessarily changes stack
frames. It loads original models once per group, uses the real public APIs, and
runs model groups in separate processes. Its error capture is test tooling only.
The ordinary TCK runner independently checks expected results/error flags with
its existing comparator. No expected-value assertions were weakened.

Focused tests exercise every supported table hit policy and COLLECT aggregator,
UNIQUE/ANY conflicts, priority errors/ties/multi-output shaping, defaults and
incomplete defaults, empty COLLECT/COUNT, input/condition/output/default failures,
provided and memoized dependencies, cycles, final coercion errors, upfront
failures, absent source IDs, boxed branches/quantifier skips, repeated/nested BKM
tables and direct invocations, services, reentrant capture, caller inexact traps,
redacted host failures and interrupted BKM work caught at the host boundary.
Counting registered host functions prove that inputs, matched outputs and
priorities execute the same number of times. Unmatched outputs and skipped
conditions/bodies include deliberately malformed text, proving no replay occurs.
All parsers, clients, evaluators and model functions are real; none is mocked.

## Wedge reproduction and compatibility observations

The existing temporary path-dependency harness at
`/private/tmp/boxic-wedge-xml-checkpoint` points at this worktree's applications,
without changing Wedge's committed dependency configuration:

```sh
cd /private/tmp/boxic-wedge-xml-checkpoint
BOXIC_DMN_HEX_BUILD=1 MIX_ENV=test mix run trace_probe.exs
```

It requires the original Wedge `qualify.exs`, helper, fixtures and engine-only
ExUnit suites, then compares traced/ordinary native and frozen TCK evaluations.
Two obsolete baseline observations are replaced strictly in temporary compiled
strings: malformed FEEL must now fail explicit preflight (accepted validation
checkpoint), and the new named trace APIs must exist and return a decision event
with the actual `RefundEligible` source ID. The original assertion that ordinary
`evaluate(..., trace: true, timeout: 0, max_steps: 0)` returns its existing
untraced result remains unchanged. No execution budget is thereby added.

The first harness run intentionally retained the original no-trace-API observation
and reported 25/26 passes, with only that now-obsolete assertion failing. After
replacing it with positive API/event assertions, all 26 pass. Wedge files on disk
are unchanged. Its application dependency smoke test is not part of these 26
engine-only tests. Logs and temporary harness code are under `/private/tmp/boxic-trace-*`
and the harness directory; committed tests/scripts do not require Wedge.

## Separate semantic findings and remaining limits

Successful FIRST traces must not be presented as a short-circuit implementation:
the base scans all rules and evaluates all matched outputs. An error in a later
matched output still fails FIRST; the regression preserves this result.

A pre-existing **scalar numeric PRIORITY/OUTPUT_ORDER defect** was found while
building positive trace tests. In the unchanged `rank_result/3`, `is_map(result)`
also matches a Decimal struct, so scalar numeric results are treated as shaped
output contexts and fail with `:output_not_in_priority_values`. String priorities
and genuinely shaped multi-output priorities succeed and have dedicated tests.
The new negative test explicitly records the unchanged numeric limitation; a
green limitation test is not a conformance claim. No ranking correction is mixed
into tracing. The only priority-helper refactor carries existing sorted indices
alongside the values to record contributions without re-evaluating priorities.

Caller Decimal precision/rounding and propagated inexact traps remain unchanged.
Empty COLLECT, including the observed COUNT path, still returns nil. No wider
exponent/overflow/underflow, containment, XML subprocess timeout, CPU/heap/step
limit or dependency advisory correction is included. Existing XML editor/writer
fidelity boundaries remain accepted and unchanged. Trace values can be large and
can contain business inputs/callables; downstream serialization, storage and
application evidence policies remain outside this library task.

## Prepared upstream PR description

**Title:** Add opt-in DMN evaluation traces from the actual execution

Add `evaluate_with_trace` and `evaluate_service_with_trace` while preserving the
ordinary APIs, errors and evaluation scheduling. Traces include decision and
dependency visits, actual table inputs and cells, matched versus contributing
rules, defaults/no-match outcomes and partial failure evidence. Source IDs remain
optional; positional/invocation references are identified explicitly.

A scoped in-process collector records the existing evaluator, including FEEL
callbacks, without replaying expressions. Reentrant calls are isolated and state
is restored on exceptional returns. Trace data remains native, untruncated and
unstored. FIRST's eager matched-output behavior and existing arithmetic/priority
limitations are preserved and documented separately.

Validation: 216 ExUnit tests; strict formatting/compilation, Credo and Dialyzer;
1,485 exact traced/untraced comparisons and expected-result DMN TCK passes at
`a162739d...`; 2,042 FEEL TCK passes with 18 existing Java exclusions. Selected-suite
evidence is not certification. Review against accepted `83032a0`; no application
integration, arithmetic corrections, execution limits or dependency bumps.
