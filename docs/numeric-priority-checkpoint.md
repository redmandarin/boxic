# Scalar numeric priority review checkpoint

Base: accepted tracing commit `9d7a944feb111f1358c999bbc2368e8a9236a381`.
Branch: `fix/numeric-table-priorities` in `/private/tmp/boxic-xml-preserving-edits`.
The original contributor instructions were read explicitly from
`/Users/pg/Documents/Code/projects/boxic/AGENTS.md`.

## Fix and compatibility

PRIORITY and OUTPUT_ORDER previously rejected scalar Decimal outputs because
`rank_result/3` mistook every map for a compound output context. A separate
structural-equality comparison also rejected numerically equal values such as
`1.0` and `1.00`.

Ranking now receives the complete table and selects the value from its declared
output shape: one output uses the result directly; multiple outputs extract the
existing priority output from the shaped result context. Priority membership
reuses `Boxic.FEEL.Semantics.equal?/2`, whose Decimal clause uses numeric equality.
The rule's original value is returned unchanged; matching does not normalize
scale, coerce strings, introduce tolerance or route values through floats.

The standard basis is [DMN 1.5, formal/24-01-01](https://www.omg.org/spec/DMN/1.5/PDF):
8.2.6 and 8.2.11 (body headings) define output-value priority order; 10.3.2.10 distinguishes
single output values from compound contexts; 10.3.2.3.1 defines numeric values
independently of their equivalent coefficient/scale representations. Numeric
comparison also agrees with the real FEEL evaluator in the new regression cases.

The accepted trace module and API are unchanged. Strings, existing multi-output
selection, stable sorting of equal ranks, first matching priority entry and the
input/matching/output/priority evaluation sequence are preserved. Existing
multi-output priority selection is not expanded into a new compound-output
ranking algorithm. Missing priorities and values not present in the priority
list retain their errors. All outputs and priorities are still evaluated exactly
as before, including matched outputs that do not contribute to PRIORITY's result.

The old numeric-priority limitation assertion has been replaced by positive
result and contributing-rule assertions. The prior tracing checkpoint report is
historical evidence of the defect at `9d7a944`; this checkpoint supersedes that
limitation. No Decimal context/rounding, empty-COLLECT, execution-limit, XML,
dependency or Wedge pin change is mixed into this fix.

## Verification

Runtime: installed Elixir 1.20.4 / OTP 28.5.0.8, macOS ARM64. The repository's
Elixir 1.20.0 / OTP 29.0.1 pin is unavailable locally and remains a CI check.
The repository lock remains Decimal 3.1.1 / tz 0.28.2. Source/package provenance
is unchanged from [the reconciled baseline](qualified-package-baseline.md).

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test apps/boxic_dmn/test/evaluation_trace_test.exs
mix quality
mix test
mix tck --suite dmn --profile implemented
MIX_ENV=test mix run --no-start scripts/verify_trace_tck.exs
```

| Check | Result |
| --- | --- |
| Focused ordinary/traced tests | 46 passed |
| Full ExUnit suite | 221 passed: FEEL 36, DMN 162, TCK tooling 23 |
| Formatting, strict compilation, strict Credo, Dialyzer | Passed, no suppressions |
| Root test alias's implemented FEEL TCK profile | 2,042 passed; 18 existing Java external-function exclusions |
| Implemented DMN TCK profile | 1,485 passed; no failed/error/unsupported/missing result |
| Exact traced/untraced TCK comparison | 1,485/1,485 result assertions agree |
| Isolated Wedge-pin harness (Decimal 3.2.0 / tz 0.28.4) | 72 passed: 46 priority/tracing tests plus 26 existing engine qualification tests |

TCK pin: **`a162739daee85fb28e9d3bec2f306505992dae0f`**. Relevant included
groups are `0006-simpletable-P1`, `0007-simpletable-P2`, `0110-outputOrder-hitpolicy`,
`0113-outputOrder-hitpolicy-singleinoutcol` and `0118-multi-priority-hitpolicy`.
These five groups supply 15 result assertions within the executed 1,485-case
profile. These are selected-profile results, not complete current-corpus certification.
The new numeric/scale regressions add evidence not supplied by string-priority
TCK examples alone.

New tests compare real ordinary and traced execution, assert successful exact
results and contributing source rule IDs, and cover:

- Scalar numeric priorities and different Decimal scales, including negative
  values, signed zero and exponent notation; direct FEEL equality counterparts.
- Duplicate numerically equal priority entries and matching outputs of different
  scales, preserving first-priority selection and source rule order on ties.
- Numeric input/output/priority expressions registered through the real external
  function API, with exact call counts for both execution modes.
- Context-valued single outputs even when their member name matches the output
  clause name, preventing a replacement Decimal-only type heuristic.
- Multi-output numeric ranking across scales, original shaped results and ties.
  Existing string, multi-output, error, default and no-match regressions remain.

The existing temporary harness at `/private/tmp/boxic-wedge-xml-checkpoint` was
run with `BOXIC_DMN_HEX_BUILD=1 MIX_ENV=test mix run priority_probe.exs`. It points
at this worktree, requires the accepted tracing harness and this test module, and
leaves Wedge's committed files untouched. Its two already-documented in-memory
assertion updates cover the accepted syntax-validation and tracing APIs; all
execution-limit, Decimal-context and COLLECT observations remain unchanged.
Native invoice/refund and 24 frozen selected-TCK traced/ordinary comparisons also
pass. The extra priority tests therefore exercise both the repository Decimal
3.1.1 lock and Wedge's Decimal 3.2.0 pin without changing either.

No internal parser/evaluator/policy is mocked, and there is no second evaluation
to construct trace evidence. Private logs are `/private/tmp/boxic-priority-*`.
The original root checkout and its untracked AGENTS.md are preserved. Existing
temporary dependency/build symlinks are excluded from commits. Nothing is pushed
or published; stop here for independent review.

## Prepared upstream PR description

**Title:** Fix numeric decision-table priority ranking and Decimal equality

PRIORITY and OUTPUT_ORDER misclassify Decimal structs as compound output contexts
and use structural equality to find priority values. Rank by the table's declared
single/multiple output shape and reuse FEEL numeric equality, so values such as
`1.0` and `1.00` match while original result representations remain unchanged.

Positive ordinary/traced regressions cover numeric results and contributing rule
IDs, scale/sign/exponent equivalence, stable ties, scalar contexts, multi-output
values and evaluation counts. String priorities and existing error/default paths
remain covered. Validation: 221 ExUnit tests, all quality gates, 1,485 DMN TCK
passes and exact trace-equivalence comparisons, plus 2,042 FEEL TCK passes with
18 existing Java exclusions at revision `a162739d...`.

No Decimal context, empty-COLLECT, execution-limit or dependency change is included.
