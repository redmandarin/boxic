# First review checkpoint: source baseline and expression validation

Date: 2026-10-26. Branch: `improve/expression-validation`.

## Baseline and scope

The preserved upstream baseline is
`8c1706fadd89aa328d56c39e86edd49708876479`, a descendant of the supplied main
`0eaeb0c3e16fa0e85533f063a0198ad7daf71683`. Its runtime and schema contents
match the qualified Hex releases exactly; release metadata differs. The
[provenance report](qualified-package-baseline.md) and [file hash manifest](qualified-package-baseline.json)
record the exact comparison. Provenance commit: `b9ef13d`.

This checkpoint implements only supported-expression validation. See the
[API, coverage and compatibility documentation](expression-validation.md).
XML editing and evaluation tracing remain for subsequent reviewed work. No
writer/fidelity behavior, hit-policy behavior, Wedge source/configuration or
dependency pin changed. No push, release or PR creation occurred. The existing
untracked repository `AGENTS.md` is preserved outside these commits.

## Verification

Actual runtime: Elixir 1.20.4, OTP 28.5.0.8, macOS ARM64. The repository pins
Elixir 1.20.0 / OTP 29.0.1; those exact tools are unavailable locally. Checks
used the installed newer Elixir with OTP 28, matching Wedge's qualification
runtime. Runtime compatibility on the exact repository OTP 29 pin remains a
CI check. Repository lock: Decimal 3.1.1 / tz 0.28.2. The isolated Wedge harness
uses Decimal 3.2.0 / tz 0.28.4, matching Wedge's current lock.

Commands use this runtime on PATH:

```sh
export PATH=/Users/pg/.asdf/installs/elixir/1.20.4-otp-28/bin:/Users/pg/.asdf/installs/erlang/28.5.0.8/bin:$PATH
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix quality
mix tck --suite dmn --profile implemented
MIX_ENV=test mix run --no-start scripts/validate_tck_expressions.exs
```

| Check | Result |
| --- | --- |
| Formatting and strict project compilation | Passed |
| Full ExUnit suite | 160 passed: FEEL 36, DMN 101, TCK tooling 23 |
| `mix quality` (format, strict compile, strict Credo, Dialyzer) | Passed, no Dialyzer errors or suppressions |
| Root test alias's implemented FEEL TCK profile | 2,042 passed, 18 explicitly unsupported Java external-function cases |
| Implemented DMN TCK evaluation profile | 1,485 passed, 0 failed/error/missing/unsupported |
| Explicit static validation of implemented DMN TCK models | 69/69 passed without business inputs |
| Wedge's unchanged qualification runner under repository lock | Native examples pass; selected TCK 24 passed; writer 10 unsupported |
| Isolated Wedge qualification tests under Wedge's numeric/timezone pins | 26 passed, with the fixed preflight-gap assertion updated |

TCK revision: **`a162739daee85fb28e9d3bec2f306505992dae0f`**, from the
vendored pin and Wedge's frozen manifest. The Boxic implemented profiles are
selected vendored suites, not a claim about the entire current upstream corpus
or certification. The static check validates 69 unique models, not 1,485 separate
models. It exposed a valid multiword import alias in `0089-nested-inputdata-imports`;
the regression now uses the original vendored XML with an explicit import map.

The regression matrix exercises malformed and valid XML-loaded counterparts in
28 supported positions, including recursive component allowed values. Additional
tests cover deep boxed nesting, skipped branches, unused defaults, unmatched
outputs, short-circuited rule conditions, distinct unary grammar, strings with
commas, ordered local scopes, parameters, typed fields, collection context keys,
unsupported languages and unchanged ordinary result/error behavior. Internal
application functions are never mocked.

An initial Dialyzer run exposed OTP 28's opaque MapSet representation mismatch
in new type-cycle tracking. Replacing that small visited set with a plain list
removed the mismatch; the final gate passes without suppressions. Initial
dependency compilation emitted ExDoc/tz warnings, and PLT construction emitted
xmerl specification warnings. Final strict project compilation and analysis pass.

## Wedge reproduction without dependency changes

The unchanged runner was invoked from the Boxic root:

```sh
MIX_ENV=test mix run --no-start /Users/pg/Documents/Code/projects/yv/tasks/decision_models/02_contracts/qualify.exs
```

The second run used `/private/tmp/boxic-wedge-checkpoint`, a standalone Mix
project with path dependencies on this fork's two applications, Decimal
`== 3.2.0` as an override, and Jason. `BOXIC_DMN_HEX_BUILD=1` selects the
existing non-umbrella dependency branch; it is not a new production switch.
The resolved timezone dependency is tz 0.28.4. Commands:

```sh
cd /private/tmp/boxic-wedge-checkpoint
BOXIC_DMN_HEX_BUILD=1 MIX_ENV=test mix deps.get
BOXIC_DMN_HEX_BUILD=1 MIX_ENV=test mix run probe.exs
```

The harness requires Wedge's original qualification helper and runner by
absolute path, then runs its two engine-only ExUnit files. It replaces exactly
one now-obsolete assertion, in a temporary in-memory copy of
`xml_qualification_test.exs`:

```elixir
# Former limitation observation:
assert :ok = Boxic.DMN.validate(model, for: :evaluation)

# Required fixed behavior:
assert {:error, [%{
  code: :invalid_feel_syntax,
  category: :feel,
  path: [:decisions, "RefundEligible", :expression, :text]
}]} = Boxic.DMN.validate(model, for: :evaluation)
```

Its existing runtime invalid-syntax assertion remains unchanged. All other
assertions run unchanged, including exact arithmetic boundaries, caller decimal
context, XML safety/resource checks, containment observation, fidelity refusal,
coercion limitations and missing traces. The dependency smoke test belongs to
Wedge's application harness and is not among these 26 isolated engine tests.
The harness also explicitly preflights both native models and all ten selected
TCK models. Wedge's committed dependency files and test sources are untouched.

The frozen selected TCK groups are `0001-input-data-string`,
`0002-input-data-number`, `0003-input-data-string-allowed-values`,
`0004-simpletable-U`, `0008-LX-arithmetic`, `0010-multi-output-U`,
`0114-min-collect-hitpolicy`, `0115-sum-collect-hitpolicy`,
`0116-count-collect-hitpolicy`, `0119-multi-collect-hitpolicy`. Wedge's existing
Decimal error comparator remains strictly below `0.00000001`; three mortgage
expectations differ beyond their rounded digits. Native boundary tests remain
exact, with no numeric normalization added.

Private logs and temporary reproduction code are under `/private/tmp/boxic-*`.
The committed parser tests, static TCK script and API docs are independent of
Wedge and do not require its checkout.

## Remaining limitations and next review boundaries

Syntax validation does not establish runtime success or a complete admission
policy. It uses the engine's supported FEEL parser/normalizer, not a newly
implemented full normative grammar or a name/type checker. Unsupported normalized
DMN expressions and languages remain distinct errors; parser rejection is bounded
to its supported grammar. Input-dependent names/types, host calls and arbitrary
dynamic context keys remain runtime concerns. Loading alone still does not
perform full syntax validation; consumers must call capability validation.

Qualification's arithmetic and containment issues remain unchanged: division
uses caller Decimal precision/rounding (six versus 34 digits reproduced); default
rounding is half_up; broader exponent/overflow/underflow/NaN behavior remains
unqualified. Empty COLLECT, including COUNT in the observed cases, returns nil.
Unknown evaluation timeout/max-step options still do not impose budgets. XML
depth/node bounds apply after tree construction, and the schema subprocess has
no qualified public timeout. The existing locked Decimal advisory is recorded
in the provenance report; no dependency upgrade is smuggled into validation.

The current writer and concrete table editor still refuse documents whose
unsupported content cannot be retained. No promise of description, annotation,
namespace, DMNDI or extension preservation is added here, and no general editing
API is introduced. Tracing remains absent; this checkpoint does not re-evaluate
expressions to synthesize traces. Later work needs its own editing boundary and
trace API review before implementation, as requested.

## Prepared upstream PR description

**Title:** Validate supported DMN expression syntax without executing models

Schema-valid DMN containing malformed FEEL such as `if )` currently passes
capability preflight and fails only if execution reaches it. Evaluation and
authoring validation now parse all supported expression positions, including
unselected branches, unmatched outputs, defaults and recursive allowed-value
tests, with positioned FEEL diagnostics and no business inputs.

The change reuses the FEEL parser and adds a syntax-only unary-test entry point.
Declared names, local scopes and import aliases inform parsing without fabricated
values. Ordinary evaluation and service evaluation retain their existing
preflight, result/error shapes and expression scheduling. Structural loading and
serialization/fidelity validation remain unchanged. Full coverage and the
intentional stronger capability-validation behavior are documented.

Validation: 160 ExUnit tests; formatting, strict compilation, Credo and Dialyzer;
2,042 FEEL TCK passes with 18 known Java exclusions; 1,485 implemented DMN TCK
passes; explicit preflight of all 69 selected DMN models. TCK revision
`a162739daee85fb28e9d3bec2f306505992dae0f`. These are selected-suite results,
not certification. No XML editor, tracing or application-specific integration
is included.

**Review base:** upstream `8c1706f`, whose executable source matches Hex DMN
0.3.0 / FEEL 0.2.0. Upstream main is older; target the verified source branch or
wait for that history to reach main. Do not present the six pre-existing upstream
commits as newly authored improvements. The provenance-only commit can be
reviewed separately from the implementation commit.
