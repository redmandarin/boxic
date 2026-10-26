# Scoped FEEL arithmetic contract

Base: accepted numeric-priority work `b61d3a2` and documentation `25b02ea`.
This design is recorded before implementation. Empty-COLLECT, dependency pins,
XML behavior and numeric literal/input admission are outside the runtime change.

## Context and entry points

Every public FEEL evaluation form (source, AST, unary tests, with/without options)
and DMN decision/service/traced entry point runs in an explicit Decimal context:
precision 34, rounding `:half_even`, fresh flags, adjusted exponent bounds
6144/-6143 and traps for invalid operation, division by zero and overflow.
Inexact, rounded and underflow signals do not inherit caller trap settings.

`Decimal.Context.with/2` restores the caller's entire context on normal returns,
tagged errors, exceptions, throws and exits. Nested public calls establish the
same fixed arithmetic policy and restore the enclosing context. No cached active
flag or global application configuration is introduced. Internal DMN aggregation
therefore runs under the policy even outside an individual FEEL expression.
Trusted host functions see the execution context; arbitrary unbalanced mutation
of process state by a host is not made a sandboxed capability.

The shared arithmetic module has two concrete responsibilities: scoped context
ownership across the FEEL/DMN application boundary, and local numeric-result
translation. Existing parser, evaluator and collection scheduling remain real.

## Numeric failures and explicit rounding

[DMN 1.5](https://www.omg.org/spec/DMN/1.5/PDF), 10.3.2.3.1 (printed p.107),
specifies 34 digits, nearest-even rounding, and null instead of NaN/infinity.
Tables 57 and 59 in 10.3.2.15 define arithmetic domain/scale failures and
zero-divisor results. Numeric failure translation belongs around the arithmetic
operation after operands have been evaluated, not around the whole execution.

Only Decimal errors carrying `:invalid_operation`, `:division_by_zero` or
`:overflow` become `{:ok, nil}` in binary/unary numeric operations, pure built-in
computation and DMN SUM. Nonfinite direct numeric results also become null.
Native `ArithmeticError` is translated only inside the existing float-math kernels
used by fractional power and numeric functions, not arbitrary callbacks. Other
exception classes and Decimal signals are not newly swallowed. Existing host
redaction and the built-in error boundary remain unchanged. Nulls remain local:
`[undefined_numeric_calculation, 1]` retains its list structure.

Explicit round/floor/ceiling/round-up/down/half-up/down built-ins retain their
specified modes. The engine arithmetic context does not replace each function's
explicit rounding argument. Syntax validation and parsing alone are not new
arithmetic evaluation entry points.

## Deliberate audit boundary

Context configuration does not retroactively round or validate literal/context/
AST values, freeze arbitrary external function implementations, or establish
complete decimal128 conformance. Audit construction and exponent boundaries in a
separate record, including differences between the locked Decimal version and
Wedge's version, subnormal/underflow handling and float-backed math. No unapproved
literal rejection, coefficient normalization, exponent algorithm rewrite or
resource limit is included merely to make the arithmetic-context tests pass.
