# Changelog

All notable changes to `boxic_feel` will be documented in this file.

## Unreleased

- Run all public evaluation entry points in a scoped 34-digit, half-even Decimal
  context, restoring caller precision, rounding, bounds, flags and traps on exit.
  Translate identified arithmetic failures to local FEEL nulls without rescuing
  whole evaluations or provider/programming errors. Preserve explicit rounding
  built-ins; numeric construction and exponent conformance remain separate.

- Add `Boxic.FEEL.validate_unary_tests/1` for syntax-only validation using the
  unary-test grammar (dash, alternatives and negation), without evaluating operands.

- Add options-aware expression, AST, and unary-test evaluation with a private
  trusted external-function environment.
- Keep built-ins ahead of registered functions by default, allow explicit host
  opt-in to registered precedence, and redact host exceptions.

The project follows Semantic Versioning. While the package is below version
1.0.0, breaking changes increment the minor version.

## 0.1.0 - 2026-07-18

- Initial public release.
- Parse and evaluate FEEL expressions with decimal number semantics.
- Support FEEL collections, contexts, ranges, functions, temporal values, and
  Level 3 built-ins.
- Provide an allowlisted Elixir external-function boundary.
- Target DMN 1.4 and use the IANA timezone database through `tz`.
- Validate against DMN TCK revision
  `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`.
- Pass 2,042 cases in the pinned FEEL TCK profile, with the 18 Java-specific
  external-function cases reported as intentionally unsupported.

### Final bounded-v1 qualification iteration

- Require qualified Decimal 3.2.0; unify bounded nearest-even numeric admission,
  reject nonfinite/out-of-domain values with tagged errors, retain exact subnormals
  and return local null for arithmetic inexact underflow. Remove mean's extra
  post-rounding and use Decimal.sqrt for sqrt/stddev.
- Add `Boxic.FEEL.Profile` and `evaluate_bounded/3`; deferred mathematics and
  dynamic call paths are explicitly excluded from the opt-in bounded_v1 profile.
- Add the monitored `Boxic.FEEL.Execution.run/2` deadline/GC-heap boundary.

### Dynamic integer-power review correction

- Admit dynamic integer exponents under bounded_v1 and enforce integer, OMG-domain
  and resource checks at execution across source, AST, unary and bounded APIs.
- Keep fractional powers excluded and legacy unprofiled power capability intact.
- Avoid an unused terminal square that could overflow a valid large ** 1.
