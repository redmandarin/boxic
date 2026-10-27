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
check the exponent's domain, integrality and magnitude before conversion to a
native integer or entering integer exponentiation. An out-of-OMG-domain value or
null produces FEEL null; a fractional value inside the OMG domain returns
`:unsupported_profile`; an integer outside the resource cap but inside the OMG
domain returns `:execution_limit_exceeded`. Existing wrong-base type diagnostics
remain. Skipped powers perform no runtime exponent check. Fractional powers never
reach binary-float math in this profile.

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
