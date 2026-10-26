# Decimal context and empty-COLLECT recommendations

Historical proposal recorded at `25b02ea`. The scoped arithmetic portion is now
implemented in [the arithmetic correction](scoped-feel-arithmetic.md); the
construction/exponent audit remains separate. The COLLECT recommendation stands.

Documentation only, separate from the scalar numeric priority fix. These are
recommendations for review, not implemented behavior changes or authorization
to change Wedge's pins. Normative references use
[DMN 1.5, formal/24-01-01](https://www.omg.org/spec/DMN/1.5).

## Decimal arithmetic context

DMN 1.5 [10.3.2.3.1, printed p.107](https://www.omg.org/spec/DMN/1.5/PDF#page=115)
specifies 34-digit, nearest-even arithmetic. It treats coefficient/scale pairs
with the same numeric value as equal and excludes infinity and NaN as FEEL
number values. This supports numeric priority equality; it does not require
changing the representation of a returned Decimal.

Boxic currently inherits the caller's Decimal context. Qualification reproduced
different division precision at 6 and 34 digits. Decimal's documented default
rounding is `:half_up`, while `:half_even` implements nearest-even. Its context
is process-local, flags are sticky, and configured traps can raise. See the
primary [Decimal.Context documentation](https://decimal.hexdocs.pm/Decimal.Context.html).

Recommended future change: establish an explicit engine arithmetic context with
precision 34 and rounding `:half_even` at evaluation boundaries. Preserve and
restore the caller's full context, including flags/traps, on success and failure;
`Decimal.Context.with/2` provides the scoped mechanism. Internal synchronous
BKM/function/service work should share the execution context. Plan this across
standalone FEEL, DMN, services and traced entry points rather than applying a
global application setting or changing selected operators only.

That proposal needs separate compatibility review and tests before implementation:
positive/negative halfway ties with even and odd retained digits; inexact division;
caller contexts with different precision/rounding/traps; context restoration after
tagged errors and propagated exceptions; nested/reentrant calls; all evaluation
entry points; and exponent/subnormal/overflow behavior. Do not trap ordinary
inexact rounding merely because the caller does. Define how numeric exceptional
conditions map to FEEL null separately from programming/provider failures.

An arithmetic context alone does not validate existing values or every literal.
Audit parsing, number construction, external values and exponent handling against
the supported FEEL domain. Decimal documents that its exponent settings constrain
operation results, not previously created values. Preserve explicit rounding
built-ins' own specified modes, and use exact tie/boundary assertions rather than
a TCK tolerance to qualify the future change. No context/trap/rounding change is
made in the priority fix.

## Empty COLLECT is a table no-match question

DMN 1.5 [10.3.2.10, printed pp.118–119](https://www.omg.org/spec/DMN/1.5/PDF#page=126)
places the no-match/default branch before hit-policy aggregation: an authored
default supplies the result, otherwise the table returns null. Separately,
[10.3.4.4, printed p.143](https://www.omg.org/spec/DMN/1.5/PDF#page=151)
defines direct list functions: empty count is zero, while empty sum/min/max
produce null. Those list-function results do not bypass a table's no-match branch.

Recommended disposition for the current DMN 1.5 profile: **retain**
`{:ok, nil}` for no-match COLLECT without a default, including COUNT. Retain
evaluation of the table's default when supplied. Do not normalize raw COLLECT
to `[]`, or table COUNT to zero, solely from `count([])` or another engine's
behavior. The prior qualification's nil observation is not, by itself, a defect.

Preserve the distinction between no matching rules and matching rules with null
outputs. A future standards review should use separate cases for both, with and
without defaults and for each aggregator; current matching/aggregation behavior
must not be silently reinterpreted. Existing ordinary/traced no-match/default
regressions already protect the observed table behavior.

The pinned TCK `0116-count-collect-hitpolicy` fixture at
`a162739daee85fb28e9d3bec2f306505992dae0f` exercises positive match counts
(4, 1 and 2), not the empty-table case. Do not claim that those cases settle
no-match semantics. Broader profile/version changes and any independent ordered
policy no-match discrepancies need their own scope; none is corrected here.

## Review boundary

The priority fix changes only output-shape selection and numeric priority
membership. This document proposes a future arithmetic-context contract and
recommends retaining the current DMN 1.5 COLLECT no-match result. It adds no
runtime switches, exception translation, limits, persistence or dependency change.
