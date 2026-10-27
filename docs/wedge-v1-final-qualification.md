# Final Wedge-v1 Boxic qualification checkpoint

Date: 2026-10-27. **Integration candidate: `f3368d3c6779dc163a3f0220213c8b234db3345e`.**
This is the exact runtime source recommended for review and eventual Wedge
integration of **both** Boxic applications, subject to the environment check below.
It is local and unpushed. The companion report/tooling commit adds no runtime code.
No Wedge application source or committed dependency configuration changed.

## Provenance, commits and environment

The [baseline reconciliation](qualified-package-baseline.md) established
`8c1706fadd89aa328d56c39e86edd49708876479` as byte-identical runtime/schema source
for the previously qualified Hex boxic_dmn 0.3.0 / boxic_feel 0.2.0 packages.
Package metadata differs; the source version declarations are not release proof.
This iteration continues accepted scoped arithmetic `9363db7` and audit `3288588`,
retaining the accepted XML-editing, tracing and priority history and all upstream
ancestry. The root AGENTS.md was read explicitly. Work is in
`/private/tmp/boxic-xml-preserving-edits`, branch `fix/scoped-feel-arithmetic`;
the root checkout and its untracked AGENTS.md remain unchanged.

| Commit | Scope |
| --- | --- |
| `791ec5e` | Common bounded numeric admission, Decimal 3.2.0, mean post-rounding correction |
| `4eca5c7` | Enforced conservative capability profile, Decimal sqrt/stddev |
| `f9b732f` | Nested numeric admission and distinct numeric-domain validation diagnostics |
| `ea78770` | Domain-agnostic public name `:bounded_v1` |
| `e324e02` | Optional deadline/heap worker, retained trace budget, native XML ownership/cleanup |
| `f3368d3` | Fractional-duration constructor closure and tagged invalid at-literals |

Boxic now requires **Decimal == 3.2.0**; the lock records that version. It fixes
rounding carries, division/sqrt rounding and exact subnormal loss relevant to this
work, rather than carrying unexplained 3.1.1/3.2.0 behavior. See the primary
[Decimal release changelog](https://hex.pm/packages/decimal/3.2.0/files/CHANGELOG.md?fallback=default)
and [context documentation](https://decimal.hexdocs.pm/3.2.0/Decimal.Context.html).
Root qualification uses tz 0.28.2; the isolated Wedge harness uses Decimal 3.2.0 /
tz 0.28.4. No application version bump, package publication or release tag is made.

Actual runtime: **Elixir 1.20.4 / OTP 28.5.0.8 (ERTS 16.4.0.7), Darwin ARM64**;
xmllint/libxml 2.9.13 and POSIX `kill`. The source requires Elixir `~> 1.20.0`;
the worker uses supported BEAM heap flags including shared-binary accounting
([OTP documentation](https://www.erlang.org/docs/27/apps/erts/erlang.html#process_flag/2)).
The intended repository CI combination **Elixir 1.20.0 / OTP 29.0.1 / Linux** is
**unverified locally**: those runtime installations are absent and Docker reports
that its daemon is not running, including outside the sandbox. Existing CI is not
triggered because this execution may not push. Passing that exact target is a
remaining integration/release gate, not an inferred pass from macOS.

The source's historical DMN 0.2.0 / FEEL 0.1.0 version declarations and dependency
metadata remain unreconciled release metadata. The qualified isolated harness
uses both application paths from the same commit, with the FEEL dependency
overridden consistently and the existing `BOXIC_DMN_HEX_BUILD=1` packaging path.
Updating only DMN while resolving a different FEEL release is **not** this tested
configuration. Future application-owned dependency adoption must bring both
applications from this candidate; no Wedge pin change is included here.

## Numeric semantics: OMG requirements versus library policy

The [pre-implementation semantics record](wedge-v1-semantics.md) records the
primary evidence and decisions. The inspected [OMG DMN 1.5 PDF](https://www.omg.org/spec/DMN/1.5/PDF)
has SHA-256 `196c80d0f483446a6e616ba096be5d44be0f8d1820684f59a41c80bfefc52e0f`.

| Behavior | Basis |
| --- | --- |
| Decimal numbers with precision 34 and nearest-even rounding | OMG 10.3.2.3.1; Table 40 examples |
| Finite numeric domain, coefficient of at most 34 digits, scale -6111 through 6176 | OMG 10.3.2.3.1 |
| Decimal/scientific literal interpreted in base ten and mapped with that precision/rounding | OMG grammar 35, 10.3.2 and 10.3.2.3.1; no binary-float intermediary |
| Null for arithmetic zero division, overflow/out-of-scale computation | OMG Tables 57/59; local arithmetic result, not whole-model fallback |
| Exact subnormals retained; inexact underflow requiring finer scale becomes null | Application of the same scale rule; Decimal 3.2.0 supplies exact subnormal arithmetic |
| `number()` conversion outside the numeric domain returns null | OMG built-in domain rule, 10.3.2.16 |
| Numeric spelling/coefficient cap 8192 bytes/digits; parsed exponent magnitude cap 20000 | Library resource/admission policy, not a wider numeric domain |
| Reject malformed/nonfinite/out-of-domain literal or caller value with a tagged input error | Library error API/profile policy; OMG does not prescribe Boxic's literal-error return shape |
| Duration spelling cap 8192 bytes; fractional seconds use the common numeric mapping | Library bounded-construction policy, without redesigning temporal semantics |
| Scoped flags/traps, restoration and worker error API | Library execution policy implementing the arithmetic contract |

The literal mapping is resolved from the number precision/rounding requirement:
a 35-digit spelling rounds nearest-even, including exact ties and carries;
Decimal.new's default lexical rejection does not define FEEL semantics. Admission
is value-aware: equivalent representations are clamped to the scale domain,
including `1e6144`, rather than equating a lexical exponent with a FEEL scale.
The genuinely unspecified part is the implementation's bounded parsing/error API
for an out-of-range literal. This profile explicitly rejects such admission;
it does not falsely attribute that diagnostic choice to an OMG SHALL.

Source literals, trusted AST/context Decimals, DMN numeric strings/Decimals and
registered host results now share the bounded mapping. Nested lists, maps,
structs and tuples are covered. Nonfinite numbers cannot pass those boundaries.
DMN's existing numeric-string type-error shape is retained; direct FEEL admission
uses `:invalid_number`. Model validation reports `:invalid_feel_number` separately
from malformed grammar (`:invalid_feel_syntax`). Both differ from a valid
calculation returning `{:ok, nil}` and from an implementation exception.

Arithmetic uses scoped precision 34, half-even, emax 6144, emin -6143, fresh flags
and explicit invalid-operation/zero-division/overflow/underflow traps. The full
caller Decimal context is restored on success, tagged error, exception and throw;
nested public evaluations restore their enclosing context. Pure numeric failures
are translated locally. Registered-provider/programming exceptions are not
silently converted into numeric null. The existing general built-in error
wrapper remains; no new whole-evaluation numeric rescue is added.

Mean no longer rounds to 14 decimal places. sqrt and stddev use Decimal.sqrt;
`sqrt(2)` retains 34 digits and `sqrt(1e6000)` succeeds. Explicit named rounding
built-ins keep their own modes. The [final numeric observations](numeric-boundaries-final.json)
retain 22 exact real-API outcomes; all restore caller context. The old
[version-comparison audit](numeric-construction-and-exponent-audit.md) is historical;
its exp observation remains legacy output, deliberately excluded below.

This is not a proof that all mathematical algorithms, conversions or executions
are correctly rounded or successful. In particular, mathematical transcendental
algorithms are not replaced by a new general-purpose mathematics library.

## Enforced DMN/FEEL profile

`:bounded_v1` is a **library capability policy**, not an OMG conformance level or
an application publication lifecycle. Before accepting a model for this profile:

```elixir
Boxic.DMN.validate(model, for: :evaluation, profile: :bounded_v1)
# :ok | {:error, [%Boxic.DMN.Diagnostic{code: ..., path: ...}]}
```

The gate uses the existing expression-position inventory and real expression /
unary-test grammars. It checks all decisions and all supported nested positions,
including unused branches, unmatched table outputs, defaults, input/output/type
allowed tests and nested item components. No fabricated inputs or model execution
are used. The inventory has 28 real-model regression positions. Structural,
version/language, FEEL syntax/domain and profile diagnostics remain distinct.

The accepted subset includes DMN 1.5 decisions and their dependency graph,
literal expressions, supported decision-table hit policies/aggregations, boxed
contexts/lists/relations, conditionals, filters/iterators and decision services,
plus the existing implemented scalar/list/context/temporal FEEL operations that
pass the gate. This builds on existing supported constructs; it does not claim
all arbitrary DMN XML is executable. Both native Wedge models pass this gate.

The following are **enforced exclusions**, including in skipped/unused work:

- exp and log, which still use binary floats and an 8-place post-round in legacy
  execution; non-integer or dynamic powers, which still use binary-float power.
- Powers except statically literal integers of magnitude at most 1024. This
  magnitude limit is profile/resource policy, not an OMG exponent restriction.
- Dynamic function calls, FEEL function definitions, BKMs, imports, boxed
  invocation/functions and external function registries/callable inputs.
- Callback-taking sort/list-replace paths. Only direct supported built-in calls
  are accepted. Aliases cannot invoke a deferred function through another name.
- References named exp/log/sort/list_replace are conservatively reserved by this
  gate, including aliases and safe data-name shadows; ordinary FEEL name/scope
  behavior is unchanged. This explicit false-positive boundary keeps the gate
  conservative rather than pretending to prove arbitrary function provenance.

The final float/reduced-precision inventory is therefore: exp/log and fractional
power deferred and blocked; sqrt/stddev switched to the existing qualified
Decimal primitive; mean's extra rounding removed. Temporal integral-component
rounding and explicit rounding functions implement their own required operations,
not hidden reduced-precision replacements. Legacy host `:float` conversions remain
available only outside this no-provider profile and are caller-chosen boundaries.

General synchronous APIs and general validation remain available. To enforce the
same gate during ordinary/traced evaluation, pass `profile: :bounded_v1`.
Syntax/capability success does not establish business input completeness, enum
membership, correct runtime types, termination or success for every input.
Existing permissive unknown-key/enum/missing-nested-field behavior remains a caller
validation responsibility, as in the original Wedge qualification.

## Public containment and trace APIs

```elixir
Boxic.FEEL.evaluate_bounded("mean([1,0,0])", %{},
  timeout: 1000, max_heap_words: 8_000_000)
# {:ok, {:ok, decimal}} | {:ok, {:error, feel_error}} | {:error, boundary_error}

Boxic.DMN.evaluate_bounded(model, "Price", inputs,
  timeout: 1000, max_heap_words: 8_000_000,
  trace: true, trace_max_bytes: 1_000_000)
# {:ok, {:ok, value, trace}} | {:ok, {:error, error, trace}}
# | {:error, boundary_error}

Boxic.DMN.evaluate_service_bounded(model, "Service", arguments, limits)
Boxic.FEEL.Execution.run(fn -> Boxic.DMN.validate(model,
  for: :evaluation, profile: :bounded_v1) end, timeout: 1000)
Boxic.DMN.validate_xml_schema(xml, timeout: 5000)
```

The bounded source/DMN/service entry points enforce the profile. Execution.run/2
is the common concrete worker boundary for other trusted library entry points;
it does not add a profile or sandbox arbitrary host effects. Options are explicit
and bounded entry points reject unknown options. Ordinary APIs retain their public
return shapes. Bounded APIs deliberately nest the ordinary/traced return so a
boundary failure cannot be mistaken for a FEEL null or tagged model error.

The guardian monitors caller death and owns one linked/monitored evaluation
worker with a monotonic deadline and max_heap_size (shared binaries included).
It never retries or re-evaluates. Success waits for worker/owner termination;
late completion messages do not leak into the caller mailbox. Boundary errors:

- `:evaluation_timeout` for deadline failure.
- `{:evaluation_worker_exit, reason}` for abrupt worker termination; `:killed`
  alone cannot prove which external kill/heap condition caused it.
- `{:evaluation_exception, kind, reason, stack}` for a captured implementation
  exception/throw/exit, preserving useful diagnostic distinctions.
- `:invalid_execution_limits` for invalid deadline/heap/options.

A timeout or killed worker cannot return a completed or manufactured partial
trace. Tagged engine failures still return the real partial trace when evaluation
returns normally. No trace is reconstituted through a second execution.

Ordinary traced APIs accept `trace_max_bytes` (default `:infinity`). Bounded DMN
APIs default to a finite 1 MB event budget. The budget measures retained events'
external-term size, with constant empty-container overhead; it is not an exact
heap ceiling or final-result quota. On exhaustion collection freezes and exposes
`truncated: true, truncation_reason: :event_size_limit`. Retained unfinished events
are incomplete evidence, not proof of skipped execution. Evaluation continues
unchanged; no extra expressions run, and matches/contributions are not invented.
One metadata/update construction can transiently exceed the retained budget.

BEAM's heap check occurs at GC. It is not an instantaneous allocation cap,
node-wide quota, native/NIF preemption guarantee or descendant-process sandbox.
Model/input/result copying, caller concurrency, host effects and stronger OS
isolation remain caller responsibilities. Whole-process dictionaries are not
inherited. Loading/validation can be wrapped in Execution.run when the caller
also needs that BEAM boundary; evaluation wrappers accept an already loaded model.

XML validation replaces unbounded System.cmd with a directly owned Port/resource
process. The owner monitors the caller, applies a native deadline, bounds retained
diagnostics to 4000 bytes, terminates owned xmllint, closes the Port and removes
its exclusively created temporary file on normal failure, timeout or caller
cancellation. Existing XML byte/depth/node/DTD/name protections remain. Native
termination/reaping may add cleanup latency. It does not promise descendant-tree,
VM-crash or OS-crash cleanup. POSIX kill and xmllint are required.

Descriptions, annotations, namespace/diagram/extension preservation and lossy
writer refusal remain the accepted XML checkpoint's bounded contract; no arbitrary
XML editing system or new executable extension semantics is introduced.

## Verification and reproduction

All final runtime checks use candidate `f3368d3c6779dc163a3f0220213c8b234db3345e`.
The shell PATH selected installed Elixir 1.20.4 / OTP 28.5.0.8 rather than the
unavailable .tool-versions combination.

```sh
mix format --check-formatted
mix format --check-formatted scripts/qualify_bounded_v1_tck.exs scripts/qualify_wedge_v1.exs
mix compile --warnings-as-errors
mix quality
mix test
mix tck --suite dmn --profile implemented
MIX_ENV=test mix run --no-start scripts/verify_trace_tck.exs
MIX_ENV=test mix run --no-start scripts/qualify_bounded_v1_tck.exs
MIX_ENV=test mix run --no-start scripts/audit_numeric_boundaries.exs
bash scripts/verify_tck_pin.sh
bash scripts/verify_license_files.sh
# In the isolated path-dependency harness, without editing Wedge:
WEDGE_ROOT=/path/to/wedge BOXIC_DMN_HEX_BUILD=1 MIX_ENV=test mix run /path/to/boxic/scripts/qualify_wedge_v1.exs
```

| Check | Final result |
| --- | --- |
| Umbrella ExUnit | 253 passed: FEEL 55, DMN 175, TCK tooling 23 |
| Formatting, strict compilation, strict Credo, Dialyzer | Passed; zero Dialyzer findings/suppressions |
| Implemented FEEL TCK | 2042 passed; 18 existing Java external-function exclusions |
| Implemented DMN TCK | 1485 passed; zero failed/error/missing/unsupported |
| Exact ordinary/traced DMN comparison | 1485/1485 assertions agree |
| Enforced bounded_v1 accepted cases | 1957 passed with exact trace agreement; 1537 capability exclusions; 51 assertions in whole negative-fixture models rejected; zero unexpected failures |
| Isolated Wedge-pin ExUnit | 102 passed |
| Native invoice/refund bounded ordinary/traced calls | Passed; no truncation |
| Wedge frozen selected TCK | 24 legacy exact comparisons pass; 21 accepted by bounded_v1, 3 explicitly excluded |
| Original qualification writer classifications | 10 fidelity refusals remain; no weakened writer assertions |
| Final numeric observations | 22 outcomes, full caller-context restoration throughout |
| Vendored TCK pin / package license checks | Passed |
| Intended pinned Elixir/OTP on Linux | Unavailable locally; not claimed as passed |

TCK revision: `a162739daee85fb28e9d3bec2f306505992dae0f`; corpus pin verification
passes. The legacy implemented FEEL/DMN profiles and the narrower enforced model
profile are different scopes. Existing TCK expected-value comparators are
unchanged (including numeric tolerances); new precision/tie/endpoint regressions
and traced/untraced comparisons use exact native results. These selected profiles
are not full conformance or certification.

The enforced-profile report separately records capability exclusions and whole
models containing deliberately invalid TCK expressions. The latter include the
three fixtures for duplicate context keys, invalid number parameter names, and
invalid at-literals. The script verifies that their failing decision is declared
an expected-error case. Their otherwise-valid siblings are also unqualified under
the whole-model gate: they are not counted as passes or silently removed to make
the corpus green. See [the full profile classification](bounded-v1-tck-qualification.json).

The committed [Wedge harness](../scripts/qualify_wedge_v1.exs) reads original Wedge
sources and uses the same three explicit in-memory assertion updates accepted in
prior checkpoints: malformed-FEEL rejection, presence/actual behavior of trace
APIs, and fixed 34-digit division plus complete caller-context restoration.
Replacement counts are checked. Wedge source files and all other original
qualification assertions are untouched. It also loads the real Boxic regression
tests and checks bounded native models plus exact selected-case equivalence.
The harness uses no mocked parser, evaluator, validator, Repo or internal path.

Containment regressions run real FEEL expansion, actual deadline/heap termination,
provider entry/caller death, full mailbox cleanup, traced failures, table capture
truncation, bounded services, real xmllint timeout and resource-owner caller
cancellation. The cancellation test observes/suspends only the actual resource
owner to queue caller death deterministically; it does not replace validation.
Temporary-file assertions are scoped to their owning VM, avoiding false failures
from independent concurrent qualification runs. No native validator double is used.

Initial verification found a completion-message mismatch, an OS-PID lookup error,
and races in cleanup test observation; those were corrected before the final
passing checks. No runtime/TCK expectation was weakened. Detailed local logs are
`/private/tmp/boxic-v1-release-*`; machine-readable profile/numeric evidence is
committed with this report.

## Review outcome and limitations

**Environment/adoption gate:** run the exact Elixir 1.20.0 / OTP 29.0.1 Linux checks
before production integration/release; ensure both application dependencies use
the same candidate source. This execution cannot claim that deployment target is
verified. No known remaining blocker was observed for the enforced bounded_v1
profile on the tested runtime and native Wedge fixtures.

**Explicitly deferred and enforced:** exp/log, fractional/dynamic or oversized
powers, arbitrary function/provider/BKM/import/invocation paths and callback sort/
list-replace are rejected before model acceptance and again by opted-in evaluation.
Legacy access to them is not qualified support. Strong OS/node/descendant isolation,
application input contracts/concurrency, arbitrary-model editing and full DMN/
mathematical conformance remain outside the promised boundary. Application
publication, storage, logging, authorization, Tools, Composer and UI remain outside
Boxic. Release metadata reconciliation is deferred to release work.

**Unchanged:** empty-COLLECT/default/no-match semantics (including COUNT), existing
hit-policy/tie ordering, ordinary evaluation shapes, application pins, XML fidelity
refusals and unsupported-content preservation boundaries. No Wedge persistence,
application changes, push, package publication or PR creation occurred.

## Prepared upstream PR descriptions

**Numeric:** Unify bounded FEEL numeric admission and qualify Decimal 3.2.0.
Previously 35-digit literals could raise while trusted Decimals bypassed admission,
nonfinite inputs escaped, exact subnormals depended on the installed Decimal
version, and mean discarded precision. Apply a common bounded nearest-even mapping,
tag invalid admission distinctly, preserve valid subnormals and local numeric nulls,
and close fractional-duration construction. Preserve caller context and explicit
rounding modes. Include real regression and pinned-suite evidence.

**Profile:** Add an opt-in conservative bounded_v1 capability gate. Check the real
expression/unary-test grammars at every supported position and reject deferred
float-backed/dynamic mathematics and function escape paths before acceptance.
Use Decimal.sqrt for supported roots/stddev. Keep legacy evaluation available and
report exclusions/negative fixtures distinctly from passing qualification cases.

**Containment:** Add opt-in single-evaluation deadline/GC-heap workers, explicit
retained trace budgets and owned native XML timeout/cancellation cleanup. Preserve
ordinary return shapes and actual execution scheduling. Document BEAM/native/caller
responsibilities and test real termination, traces, mailbox and temporary resources.
