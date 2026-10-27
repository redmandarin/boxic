# bounded_v1 dynamic integer powers: correction design

Base: final checkpoint `142c7c0`, runtime candidate `f3368d3`.
Recorded before coding the review correction. The literal-only restriction was a
static-analysis shortcut and did not satisfy the approved dynamic integer-power
contract. This correction supersedes it; other feature exclusions do not expand.

[OMG DMN 1.5](https://www.omg.org/spec/DMN/1.5/PDF), 10.3.2.15 Table 60 permits an
exponent value in [-999999999, 999999999]; 10.3.2.15's introduction maps inputs
outside semantic input domains to null. The table also specifies null for an
out-of-scale result. None of those clauses requires a literal exponent. Integer
only and magnitude at most 1024 are bounded_v1 policies, not the full OMG domain.

The static gate will recursively inspect both power operands, reject known
fractional literals and known resource-limit violations, and admit dynamic
expressions. At an actually evaluated power, evaluate each operand once, then
check the exponent's integrality, numeric domain and resource magnitude before conversion to a
native integer or entering integer exponentiation. An integer outside the OMG domain or
null produces FEEL null; any fractional value returns
`:unsupported_profile`; an integer outside the resource cap but inside the OMG
domain returns `:execution_limit_exceeded`. Existing wrong-base type diagnostics
remain. Skipped powers perform no runtime exponent check. Fractional powers never
reach binary-float math in this profile.

The integer-only profile check takes priority: fractional values are rejected even
when outside the standard exponent range. The standard domain-null rule applies
to the integral subset accepted by this profile. Non-number exponents keep the
existing tagged type-error style.

The execution profile will be carried in the existing evaluator context, as the
trusted external-function/type environments already are, rather than a new
process-global flag. Public FEEL source/AST/unary entry points with the opt-in
profile, DMN decisions/services, and bounded entry points must share this policy.
Legacy evaluation without a profile keeps its existing power capability.

The current integer-power loop also squares the base after its last required
multiplication. That unnecessary square can overflow a valid `large ** 1`. A
separate arithmetic regression/fix will remove only that unused operation, not
replace the algorithm or change rounding policy.

## Reusable logic boundary

BKMs, imports and pure user-defined functions are not inherently incompatible
with decimal arithmetic or process containment. Their blanket exclusion is a
conservative static-analysis shortcut. Essential restrictions are preventing
unqualified math/provider execution and enforcing runtime numeric/resource checks,
not prohibiting all reusable logic.

The smallest already-supported route is a named same-model decision referenced
through informationRequirement/requiredDecision, shared by consumers and exposed
through a decision service if needed. Existing dependency memoization and traces
provide single-execution evidence. This shares logic under the same bound inputs;
it is not a parameterized function invoked with different arguments.

If parameterized reuse is later required, the smallest supported extension is
same-document, first-order pure BKMs invoked through existing statically named
boxed invocations: resolve a fixed BKM, validate its body and bindings with the
existing inventory, reject provider bodies/dynamic callees and recursive cycles,
and retain the runtime profile in its evaluation context. It need not enable
higher-order FEEL functions, arbitrary imports or a general callable-provenance
framework. Imports additionally require qualification of the resolved transitive
model closure. General user-defined functions require scope/provenance checks
against aliases, callbacks and returned callables. Those are separate changes;
this correction implements none of them speculatively.

## Corrected implementation and integration recommendation

**Recommend `b4b184f7f52c346b9b38cd8ed6c0704f5cbbbccf` for both Boxic applications,
subject to pinned Linux verification below.** This replaces `f3368d3`.
`0d4081e` contains the unused-square arithmetic prerequisite; `b4b184f` contains
the dynamic integer contract correction. The companion report/tooling commit
adds no runtime code. Branch: `fix/dynamic-integer-powers`, worktree
`/private/tmp/boxic-xml-preserving-edits`. The accepted branch is preserved.

Every executed power evaluates each operand once, then applies these checks
before native integer conversion or integer exponentiation:

| Exponent condition | Result | Basis |
| --- | --- | --- |
| Fractional Decimal of any magnitude | `:unsupported_profile` tagged error | Integer-only profile policy |
| Integer outside [-999999999, 999999999] | FEEL null | OMG 10.3.2.15 input-domain mapping / Table 60 |
| Integer inside that domain but magnitude > 1024 | `:execution_limit_exceeded` tagged error | Resource policy |
| Integer of magnitude <= 1024, including 3.00 | Existing integer-power path | Numeric value, independent of Decimal scale |
| Null exponent | FEEL null | Existing null propagation |
| Non-number exponent / wrong base after exponent admission | Existing tagged type-error style | Library compatibility/error policy |

The integer-only check takes priority even for out-of-domain fractional values.
The OMG domain-null rule therefore applies to the integral subset accepted by
this profile. Arithmetic overflow/underflow and zero to a negative exponent
retain local null behavior. No fractional power can enter legacy float math.

The static gate walks both operands, rejects known fractional/resource-exceeding
literals and deferred features in skipped branches, and admits unknown exponent
values for runtime checking. A skipped dynamic power is not evaluated or checked.
Static acceptance does not promise success for every future input.

An invocation-local marker travels through the existing evaluator context,
following the existing external-function/type environments; no process-global
profile flag is introduced. FEEL source/AST/unary APIs accept
`profile: :bounded_v1`; bounded FEEL uses that same path. DMN decisions/services
attach the marker after preflight and preserve it in FEEL cells. Ordinary,
traced and bounded entry points share the actual execution and preserve their
return shapes. Failed table outputs retain real inputs, matched rule IDs and
partial output/error states without inventing successful contributions.

Legacy evaluation without the profile keeps fractional-power capability, which
remains unqualified. The separately documented final-square fix intentionally
also corrects legacy `large ** 1` and reciprocal powers. No algorithm replacement,
hit-policy change, dependency change or empty-COLLECT change is included.

## Essential restrictions versus conservative shortcuts

The bans are not fundamental OMG or decimal restrictions:

| Feature | Actual existing evaluator/library behavior | Why the current gate is conservative |
| --- | --- | --- |
| BKMs | Parameter coercion/binding, named boxed invocations and recursive FEEL BKM calls. FEEL bindings use the same `{:external_function, closure}` tag as host bindings | The direct-built-in-only gate does not distinguish pure engine-created BKM wrappers from provider wrappers or qualify recursive call graphs |
| Imports | Existing loaders resolve explicit maps/resolvers or bounded local files, check namespaces/cycles, then merge namespace-qualified nodes | Merged nodes can reuse the expression inventory. Qualification must also cover resolved transitive sources, namespaces/types, profile propagation and fidelity; a new resolver framework is unnecessary |
| User-defined FEEL functions | Function values retain parameters/body/closure; invocation binds arguments and evaluates the body in that closure | Merely allowing definitions would leave their calls rejected. A useful pure subset needs explicit lexical callee, alias/callback and recursion cases; arbitrary higher-order flow need not be opened |

The essential requirements are excluding unqualified math/provider execution,
preserving the profile in called logic, and enforcing numeric/resource checks.
Blanket bans on all pure reusable logic are static-analysis/qualification
shortcuts, not intrinsic necessities. In particular, merged imported nodes are
not invisible to the current expression inventory.

**Smallest already-supported route:** same-model named decisions linked through
`informationRequirement/requiredDecision`. The new real regression shares one
pure dynamic-power decision across two consumers, and proves one evaluated visit
plus a memoized visit under ordinary, traced and bounded execution. Decision
services can expose related outputs. No capability expansion is needed. This
shares a calculation under the same input bindings; it does not provide formal
parameters or multiple argument sets for one decision within an execution.

For later parameterized reuse, a small candidate extension is existing statically
named, same-document boxed BKM invocation, with qualified pure bodies/bindings,
known callees and rejected recursive cycles. This avoids a general callable
provenance framework. For later cross-model reuse, use the existing explicit
namespace map and merged-node validation path for pure decision-only imports.
Neither extension is implemented or claimed qualified here. Removing the bans
blindly would broaden scope; this correction does not do so.

## Verification and unavailable environment

Final runtime source is the recommendation above. Dependencies remain Decimal
3.2.0, root tz 0.28.2 and isolated Wedge tz 0.28.4. Actual runtime remains
Elixir 1.20.4 / OTP 28.5.0.8, macOS ARM64.

**Linux / Elixir 1.20.0 / OTP 29.0.1 remains unverified.** Neither pinned runtime
is installed. Both configured Docker contexts were checked outside the sandbox:
`default` cannot connect to `/var/run/docker.sock`; `desktop-linux` cannot connect
to `/Users/pg/.docker/run/docker.sock`. No working Linux daemon/remote runner is
available. No pin is changed to conceal this gap. Run the pinned Linux CI before
production integration/release; this execution does not push or dispatch CI.

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix quality
mix test
mix tck --suite dmn --profile implemented
MIX_ENV=test mix run --no-start scripts/verify_trace_tck.exs
MIX_ENV=test mix run --no-start scripts/qualify_bounded_v1_tck.exs
# In the isolated path-dependency harness:
WEDGE_ROOT=/path/to/wedge BOXIC_DMN_HEX_BUILD=1 MIX_ENV=test mix run /path/to/boxic/scripts/qualify_wedge_v1.exs
```

| Check | Corrected result |
| --- | --- |
| Repository ExUnit | 262 passed: FEEL 61, DMN 178, TCK tooling 23 |
| Format, strict compile, Credo, Dialyzer | Passed; zero Dialyzer findings or suppressions |
| Implemented FEEL TCK | 2042 passed; 18 existing Java external-function exclusions |
| Implemented DMN TCK | 1485 passed; zero failed/error/missing/unsupported |
| Exact traced/untraced DMN TCK | 1485/1485 exact result assertions agree |
| Enforced bounded_v1 TCK | 1999 passed; 1495 static exclusions; 51 negative-fixture assertions rejected by whole-model gate; zero runtime exclusions or unexpected failures in this selected corpus |
| Isolated Wedge-pin tests | 111 passed |
| Frozen Wedge selected TCK | All 24 accepted/passing under bounded_v1; exact legacy/traced agreement |
| Native invoice/refund bounded ordinary/traced calls | Passed |
| Pinned Linux / Elixir / OTP | Unavailable as detailed above |

TCK revision remains `a162739daee85fb28e9d3bec2f306505992dae0f`.
See [corrected profile evidence](bounded-v1-dynamic-power-qualification.json).
Static exclusions, runtime profile/resource rejections and whole-model rejection
of deliberately invalid fixtures are separate from passing expected-value
assertions. Runtime exclusions still require exact ordinary/traced error equality;
a trace mismatch remains a failure. Expected-value comparators and corpus are
unchanged. Selected tests do not establish full conformance/certification.

New tests cover different Decimal scales, computed/loop exponents, negative/zero
exponents, resource and OMG-domain boundaries, huge admitted exponents,
fractional/type failures, null/arithmetic failures, context restoration and
skipped work. They exercise source/AST/unary/bounded FEEL, and ordinary/traced/
bounded decisions, services and table outputs. They also prove the existing
shared-decision route. No internal parser/evaluator/validator is mocked. One
fixture constructor was corrected to use actual FEEL admission for the minimum
subnormal; expectations were not weakened. Final local logs are
`/private/tmp/boxic-power-corrected-*`.

The [previous checkpoint](wedge-v1-final-qualification.md) is historical; its
literal-only restriction and integration hash are superseded here. Other accepted
numeric, XML, tracing and containment contracts remain. Wedge mix.exs/mix.lock
are untouched and unrelated work is preserved. No push or publication occurred.
