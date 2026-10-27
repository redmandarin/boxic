# Numeric construction and exponent audit

Historical checkpoint: see [the final v1 qualification](wedge-v1-final-qualification.md) for the current numeric/dependency/profile/containment contract.

Observation-only follow-up to arithmetic correction
`9363db7660261c0040db34e3ecf28cc6fbde93e9`. This audit changes no execution,
admission, dependency, empty-COLLECT or resource-limit behavior. The
[runtime checkpoint](scoped-feel-arithmetic-checkpoint.md) records the correction
and its gates; the [arithmetic contract](scoped-feel-arithmetic.md) defines its
boundary. A configured Decimal context is not complete numeric conformance.

## Method and provenance

[`scripts/audit_numeric_boundaries.exs`](../scripts/audit_numeric_boundaries.exs)
executes 22 bounded observations through real public FEEL and DMN APIs. It
records exact coefficients/exponents, tagged failures and exceptions, including
full caller-context restoration. Its exception capture is reporting code only,
not a proposed engine error policy. Inputs use preconstructed Decimals where
needed to distinguish construction from arithmetic. No internal implementation
is mocked or replaced.

[Machine-readable observations](numeric-boundary-observations.json) record the
runtime source commit, script SHA-256, Elixir version and both Decimal versions.
Runs used Elixir 1.20.4 / OTP 28.5.0.8 on macOS ARM64:

```sh
# Boxic worktree, locked Decimal 3.1.1 / tz 0.28.2
MIX_ENV=test mix run --no-start scripts/audit_numeric_boundaries.exs

# Existing isolated Wedge harness, Decimal 3.2.0 / tz 0.28.4
BOXIC_DMN_HEX_BUILD=1 MIX_ENV=test mix run /private/tmp/boxic-xml-preserving-edits/scripts/audit_numeric_boundaries.exs
```

Both runs produced 22 observations, with the caller context restored in all
cases. These counts are observations, not conformance passes. No Wedge source,
test or committed dependency configuration changed. After committing the runtime
correction, the separate isolated qualification harness also passed all 84 tests.

## Results and boundaries

In the table, a Decimal is written as coefficient × 10^exponent. “Null” means a
successful FEEL result containing nil; it is distinct from a tagged error or
raised exception.

| Observation | Decimal 3.1.1 | Decimal 3.2.0 |
| --- | --- | --- |
| Parse or evaluate a 35-digit literal | Raises `Decimal.Error`, signal nil, number-parsing-syntax message | Same |
| Return a trusted 35-digit AST/context/DMN Decimal | Returns all 35 digits unchanged | Same |
| Add zero to that trusted Decimal | Rounds to 34 digits, half-even | Same |
| DMN number input supplied as the same 35-digit string | Tagged number type error | Same |
| Literal `1e6144` | Accepted | Same |
| Literal `1e6145` or `1e-6176` | Raises `Decimal.Error`, signal nil, parsing-syntax message | Same |
| Return trusted `1e-6176` directly | Preserved | Same |
| Trusted `1e-6176 * 1` | Zero, exponent 0 | `1 × 10^-6176` |
| Trusted `1e-6143 / 10` | Zero, exponent 0 | `1 × 10^-6144` |
| Trusted `1e-6176 / 10` | Zero, exponent 0 | Zero, exponent -6176 |
| Largest finite 34-digit coefficient × `10^6111`, multiplied by 1 | Preserved | Same |
| Same largest value multiplied by 10 | Null | Same |
| `mean([1, 0, 0])` | `33333333333333 × 10^-14` | Same |
| `exp(1)` | `271828183 × 10^-8` | Same |
| `sqrt(2)` | `14142135623730951 × 10^-16` | Same |
| `sqrt(x)` with trusted `x = 1e6000` | Existing built-in invocation evaluation error | Same |
| Return trusted NaN or DMN number string `"NaN"` | Nonfinite Decimal escapes without an arithmetic operation | Same |

The artifact retains the exact 35-digit coefficient and error details. The
runtime arithmetic guard converts nonfinite results of protected operations to
null; it does not retroactively validate every value admitted through a trusted
AST, input, return or literal construction path.

## Standard-backed interpretation and recommended next work

[OMG DMN 1.5](https://www.omg.org/spec/DMN/1.5/PDF), 10.3.2.3.1 (printed p.107),
defines 34-digit nearest-even numbers without NaN/infinities and constrains their
coefficient and scale. Arithmetic mappings in 10.3.2.15 Tables 57/59 define null
for out-of-scale results; 10.3.2.16 specifies null for built-in arguments outside
their domains. These requirements motivate the following separate work, rather
than a claim that the context correction resolves it:

1. **Construction and admission:** reconcile literal parsing, string conversion,
   trusted AST/context values and host-returned values with one documented numeric
   domain. Current constructor digit/exponent limits reject some source forms
   before arithmetic and can raise unstructured Decimal errors. Trusted values
   bypass those limits. Decide value-aware rounding/admission and structured
   diagnostics explicitly; do not merely normalize all inputs as an incidental
   side effect of evaluation. Reject or translate nonfinite admission consistently
   under the standard in that separate change.
2. **Exponent and subnormal arithmetic:** Decimal's adjusted exponent bounds are
   not FEEL's coefficient/scale domain in isolation. The endpoints depend on
   coefficient length; the largest finite value and smallest subnormal exercise
   different boundaries. Increasing a symmetric lexical exponent limit to 6176
   would also admit positive exponents beyond 6144. Decimal 3.1.1 loses valid
   subnormals in the observed operations; 3.2.0 preserves those examples, but still
   rounds the below-minimum nonzero example to zero. Reconcile that behavior with
   the standard's out-of-scale-null rule, across operations and rounding edges,
   before making a dependency or underflow-policy change. A dependency upgrade
   alone is not demonstrated to close the whole gap.
3. **Numeric algorithms:** existing binary-float conversions constrain square
   roots, fractional powers and transcendental functions. The representable
   `sqrt(1e6000)` example fails in conversion. Existing mean/exp/stddev paths also
   retain hardcoded post-rounding (14/8/13 decimal places respectively). Correctly
   rounded decimal algorithms and their error bounds need a separately scoped
   implementation and tests. The context correction adds no binary-float routes
   and does not rewrite these algorithms.

These examples do not exhaust numeric values, all math functions, lexical forms,
resource limits, serialization or conversions. Neither selected TCK passes nor
these observations establish full decimal128 or DMN conformance. Empty-COLLECT
remains unchanged, including the existing no-match/default behavior.

## Prepared upstream PR description

**Title:** Record numeric admission and exponent gaps after scoped arithmetic

Add bounded real-API observation tooling and results for Decimal 3.1.1 and 3.2.0
at the arithmetic correction commit. Separate constructor asymmetries,
nonfinite admission, version-dependent subnormals and existing float-backed math
from the scoped context guarantee. Record standard-backed recommendations and
exact observations without changing runtime behavior or claiming conformance.
