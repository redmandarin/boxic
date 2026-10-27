# Final v1 iteration: semantics and boundary decisions

Recorded before implementation, continuing from `3288588` / accepted scoped
arithmetic `9363db7`. This is a bounded library profile, not DMN certification.

## Primary numeric evidence

The locally inspected primary [OMG DMN 1.5 PDF](https://www.omg.org/spec/DMN/1.5/PDF)
10.3.2.3.1, printed p.107, defines decimal128 numbers, 34 digits and nearest-even
rounding, references precisionDecimal and BigDecimal DECIMAL128, excludes
nonfinite values, and defines `(p,s)` with at most 34 coefficient digits and
scale -6111 through 6176. Grammar 35 permits scientific notation. Section
10.3.2 says literals map directly into the semantic domain. Table 40 includes
34-digit division and exact halfway rounding examples. Tables 57/59 require null
when arithmetic requires a scale outside the valid range; division by zero is
null. Section 10.3.2.16 requires null for out-of-domain built-in arguments.

**Literal mapping:** interpreting the decimal spelling and applying 34-digit
nearest-even rounding follows the number precision/rounding requirement; the
Decimal constructor's default rejection at 35 lexical digits is not that mapping.
Trailing coefficient zeros do not change numeric value. Admission uses the same
mapping for source literals, trusted Decimal values, number strings and provider
results. Caller Decimal settings cannot alter it. No binary float intermediary
is used. Nonfinite numeric values are outside the FEEL domain.

The specification does not prescribe lexical resource limits or Boxic's tagged
input errors. The library policy bounds numeric spelling/coefficient size to
8192 bytes/digits and parsed exponent magnitude to 20000 before construction;
these are resource caps, not numeric-domain extensions. Admission rejects malformed,
nonfinite or out-of-domain values with a tagged numeric diagnostic; these are
invalid inputs, distinct from a valid computation returning FEEL null. The
standard does not explicitly specify an error API for an out-of-range literal;
rejecting it at admission is a profile policy, not a claimed mandatory OMG null
mapping. Scale is tested after precision rounding and representational clamping.

Decimal **3.2.0** is the qualified dependency: it fixes exact subnormal loss and
rounding carries. Exact subnormals down to 1e-6176 are supported. Inexact underflow
requires finer scale than the domain supports and becomes null at arithmetic
boundaries, rather than leaking Decimal's rounded zero. This deliberately uses
Tables 57/59's out-of-scale rule, not an inherited caller underflow trap. The
scope does not claim every mathematical operation is correctly rounded merely
because Decimal is configured. mean uses context division without a 14-place
post-round; sqrt and stddev use Decimal.sqrt rather than binary floats. Explicit
rounding built-ins retain their specified modes.

## Bounded mathematical profile (library policy)

The final v1 capability excludes exp, log and non-integer exponentiation rather
than inventing decimal transcendental algorithms. Validation must reject references,
including aliases and unexecuted branches, not just direct evaluated calls.
Dynamic function/provider access remains outside this opt-in profile. The final
review correction admits dynamic integer exponents with runtime checks; see
[the correction contract](dynamic-integer-powers-correction.md). This restriction must be enforceable
before a caller accepts a model, with diagnostic element/position paths and no
fabricated inputs. General legacy evaluation remains available; it is not
represented as qualified v1 execution. The profile also rejects external functions
and dynamic evaluation escapes; callers cannot use them to bypass the gate.

## Containment (library policy, not OMG semantics)

Ordinary synchronous APIs remain available. An opt-in evaluation boundary uses a
monitored BEAM worker, deadline and max_heap_size with shared-binary accounting.
It returns the actual single evaluation or an explicit boundary failure. Killing
a worker cannot provide a completed trace; boundary failures must not manufacture
one. Trace capture also gets an explicit retained-size budget and reports
truncation without changing evaluation scheduling/results. Whole-value result,
model and input sizes remain caller admission responsibilities.

max_heap_size is a GC-time process limit, not an instantaneous memory ceiling,
node-wide quota, OS sandbox, NIF preemption guarantee or descendant limit. Host
functions must not spawn unmanaged effects. Caller concurrency, request/model
sizes, supervision and stronger OS isolation are application responsibilities.
The boundary must clean up workers on timeout and caller death and avoid late
mailbox messages. XML schema validation uses a directly owned Port, a deadline,
bounded diagnostic output and temporary-file cleanup; cancellation must stop the
native validator and remove its file. No job system is introduced.

The public profile name is `:bounded_v1`: the qualification target is Wedge v1,
but the library capability and diagnostics remain domain-agnostic. Conservative
additional exclusions are callback-taking sort/list-replace, function definitions,
BKMs, imports and boxed invocation. This is intentionally narrower than the
legacy implemented TCK profile; exclusions must be reported separately from
failures and must not be represented as supported merely because legacy
execution passes them.

The final constructor scan also covers fractional duration seconds. Their
construction reuses bounded numeric admission and a scoped context; duration
spellings are capped at 8192 bytes. This cap is library policy. Invalid temporal
at-literal data returns the existing tagged literal error instead of leaking a
constructor exception. This is not a redesign of temporal arithmetic or a claim
of complete temporal conformance.
