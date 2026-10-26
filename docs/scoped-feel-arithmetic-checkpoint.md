# Scoped arithmetic review checkpoint

Base: accepted priority fix `b61d3a23eb1fd25d86ebc1acc4d7eb24454fb057`
and recommendations `25b02eac06ecaccd3db6f2ae4f62ac01b2de2349`.
Branch: `fix/scoped-feel-arithmetic` in `/private/tmp/boxic-xml-preserving-edits`.
The root checkout's AGENTS.md was read explicitly; it remains untracked and
untouched. Existing worktree build/dependency symlinks are excluded from commits.

## Runtime correction

The [arithmetic contract](scoped-feel-arithmetic.md) was recorded before coding.
All public FEEL source/AST/unary-test evaluation forms and DMN decision/service/
traced entry points now use a scoped Decimal context with precision 34 and
half-even rounding. Bounds are 6144/-6143; fresh flags and explicit numeric traps
replace caller settings during execution. `Decimal.Context.with/2` restores the
caller's complete context after normal returns, tagged failures, exceptions and
throws. Nested public calls restore their enclosing context and use the same
policy. Parsing/validation alone is not newly treated as evaluation.

The shared `Boxic.FEEL.Arithmetic` module has a concrete cross-application
responsibility: context ownership and numeric-result translation. Existing
Semantics only implements equality and cannot supply this ownership. There is
no active-context cache, configurable arithmetic mode, generic execution runner,
new worker or alternate evaluator. DMN's own SUM reduction runs under the context,
not merely the individual FEEL cells. Arguments and operands are evaluated once.

The normative basis is [DMN 1.5](https://www.omg.org/spec/DMN/1.5/PDF),
10.3.2.3.1 (34 digits, nearest-even and no nonfinite FEEL numbers), the arithmetic
mappings in 10.3.2.15 Tables 57/59, and built-in domain handling in 10.3.2.16.
At pure arithmetic boundaries, Decimal invalid-operation/division-by-zero/overflow
signals and nonfinite direct numeric results become local `{:ok, nil}` results.
Native `ArithmeticError` is handled only at the existing float-math kernels.
There is no whole-evaluation rescue: lists/contexts retain their structure when
one calculation is undefined. Parsing errors, tagged type/option/provider errors
and unrelated exceptions retain their existing paths. The pre-existing general
built-in error wrapper is unchanged; new arithmetic translation occurs inside it.

Named rounding built-ins retain their explicit modes, including half-up/down,
up/down, floor/ceiling and decimal's half-even mode. Existing float conversions
and hardcoded post-rounding in other mathematical algorithms are not silently
rewritten. Caller inexact traps no longer cause a FEEL calculation to raise.
That intentional change replaces the old trace limitation assertion with exact
result and caller-restoration assertions. Interrupted-trace coverage remains,
using an unrelated callback exception rather than disabling the new policy.

Public return shapes, evaluator options, execution ordering, trace structure,
XML behavior, and empty-COLLECT/default behavior are unchanged. No precision
normalization of arbitrary AST/context/literal values, dependency upgrade,
execution limit or Wedge pin change is included.

## Verification

Installed runtime: Elixir 1.20.4 / OTP 28.5.0.8, macOS ARM64. The exact repository
Elixir 1.20.0 / OTP 29.0.1 pin is unavailable locally and remains a CI check.
The repository lock stays Decimal 3.1.1 / tz 0.28.2. The existing isolated Wedge
harness uses Decimal 3.2.0 / tz 0.28.4 without editing Wedge's committed files.
Source/package provenance is unchanged from [the baseline report](qualified-package-baseline.md).

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix quality
mix test
mix test apps/boxic_feel/test/arithmetic_context_test.exs apps/boxic_dmn/test/arithmetic_context_test.exs apps/boxic_dmn/test/evaluation_trace_test.exs
mix tck --suite dmn --profile implemented
MIX_ENV=test mix run --no-start scripts/verify_trace_tck.exs
```

| Check | Result |
| --- | --- |
| New FEEL arithmetic tests | 8 passed |
| New DMN arithmetic tests | 4 passed |
| Arithmetic + existing tracing focused run | 58 passed |
| Full umbrella ExUnit suite | 233 passed: FEEL 44, DMN 166, TCK tooling 23 |
| Formatting, strict project compilation, strict Credo and Dialyzer | Passed, no suppressions |
| Implemented FEEL TCK profile in root alias | 2,042 passed, 18 existing Java external-function exclusions |
| Implemented DMN TCK profile | 1,485 passed, no failed/error/missing/unsupported result |
| Exact traced/untraced implemented DMN comparison | 1,485/1,485 result assertions agree |
| Wedge-pin isolated suites | 84 passed: 26 qualification, 46 tracing/priority and 12 arithmetic tests |
| Wedge native + frozen selected-TCK comparisons | Native invoice/refund results and 24 exact traced/ordinary comparisons pass |

TCK revision: **`a162739daee85fb28e9d3bec2f306505992dae0f`**. These are selected
vendored profiles, not certification or proof of complete numeric conformance.
Relevant FEEL groups include `0075-feel-exponent`, `0105-feel-math`,
`1100-feel-decimal-function`, `1101-feel-floor-function`,
`1102-feel-ceiling-function`, `1141-feel-round-up-function`,
`1142-feel-round-down-function`, `1143-feel-round-half-up-function` and
`1144-feel-round-half-down-function`; DMN includes arithmetic and collection
aggregation groups. Existing expected-value comparators are unchanged. Exact
halfway/precision tests use native Decimal equality without TCK tolerance.

The new regression matrix covers positive/negative 34-digit halfway ties with
even and odd retained digits; division under caller precision 6/34/50, distinct
rounding/bounds/flags/traps; all public FEEL evaluation forms; returned FEEL
closures; BKM, DMN SUM, services and trace equivalence; nested/reentrant public
calls inside temporary host contexts; explicit rounding modes; local numeric
nulls and SUM overflow; full restoration on tagged failures and propagated
registry exceptions/throws. Provider RuntimeError and Decimal.Error failures
remain provider errors, not numeric nulls. All application/parser/evaluator
functions are real and no internal behavior is mocked.

The Wedge harness is `/private/tmp/boxic-wedge-xml-checkpoint/arithmetic_probe.exs`,
invoked with `BOXIC_DMN_HEX_BUILD=1 MIX_ENV=test mix run arithmetic_probe.exs`.
It retains the accepted validation/trace assertion updates in temporary compiled
strings and changes one additional obsolete precision assertion: both caller
precision 6 and 34 now produce the exact 34-digit third, and each caller's full
context is restored. No Wedge test source or pin is edited. Original empty-COLLECT,
execution-budget and other qualification assertions remain. Initial temporary
harness string-delimiter and test-arity mistakes were corrected before the
reported runs; no numeric expectation was weakened to hide a failure.

## Separate audit and limitations

The numeric construction/exponent audit is observation-only, recorded separately
from the runtime correction. It compares 22 bounded cases under Decimal 3.1.1 and
3.2.0. It exposes constructor-limit errors, trusted-value admission asymmetries,
nonfinite values accepted without an operation, version-dependent subnormals,
below-minimum rounding, and existing reduced-precision/float-backed functions.
The separate audit report/tool records exact observations rather than calling
these conformance passes. No parser admission or exponent algorithm is changed
to make the context tests green. A fixed context does not establish a complete
numeric domain, correctly rounded mathematical library or resource sandbox.

The code diff was reviewed for clear arithmetic ownership, narrow exception
classification, actual single execution, complete model/entity arguments and
unchanged collection/default scheduling. Empty COLLECT remains nil without a
default, including COUNT; this is covered by existing real ordinary/traced tests.
Private logs are `/private/tmp/boxic-arithmetic-*`. Stop for independent review;
no push, publishing, PR creation, application persistence or UI work occurred.

## Prepared upstream PR description

**Title:** Scope FEEL arithmetic to 34-digit half-even Decimal execution

FEEL and DMN results currently depend on the caller's Decimal precision, rounding
and traps. Establish the supported arithmetic context across source, AST, unary,
decision, service and traced evaluation, with full caller-context restoration on
normal and exceptional exits. Include DMN aggregation and retain explicit rounding
built-ins' modes. Translate identified numeric failures locally, without rescuing
whole evaluations or provider/programming errors.

Exact tie, precision, nested-call, restoration and trace-equivalence regressions
pass alongside 233 umbrella tests, quality gates, the implemented FEEL/DMN TCK
profiles and 1,485 exact traced/untraced comparisons at `a162739d...`. The isolated
Wedge-pin run passes 84 tests. Numeric construction, exponent boundaries and
existing float-backed math remain separately audited limitations; this is not a
claim of complete decimal128 conformance. No empty-COLLECT, pin or limit change.
