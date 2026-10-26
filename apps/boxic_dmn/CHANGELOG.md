# Changelog

All notable changes to `boxic_dmn` will be documented in this file.

The project follows Semantic Versioning. While the package is below version
1.0.0, breaking changes increment the minor version.

## Unreleased

- Apply FEEL's scoped 34-digit, half-even arithmetic context to decision, service
  and traced evaluation, including table SUM, with full caller-context restoration.
  Keep no-match COLLECT/default behavior and trace scheduling unchanged.

- Fix scalar numeric PRIORITY/OUTPUT_ORDER ranking by using declared output
  shape and FEEL numeric equality, including equal Decimals with different
  scales. Preserve result representations, stable rule ties and evaluation counts.

- Add opt-in decision and decision-service evaluation traces from the same
  execution, including dependencies, table inputs/rules/outputs, matched versus
  contributing rules, defaults and partial tagged failures. Preserve ordinary
  evaluation return shapes, hit policies and expression scheduling. Trace values
  remain native terms with no truncation, storage or new execution limits.

- Add `edit_xml/3` for one supported expression/table-cell text edit selected by
  actual XML IDs. Retain loader-admitted surrounding descriptions, annotations,
  namespace bindings, diagrams and opaque extensions through xmerl document
  editing, followed by strict loading, syntax validation and preservation checks.
  Unsupported targets/content are refused; normalized writer fidelity checks
  and ordinary evaluation behavior remain unchanged.

- Evaluation and authoring capability validation now parse all supported FEEL
  expression and unary-test positions without executing the model. Malformed
  text, including skipped branches and unused defaults, returns positioned FEEL
  diagnostics. Structural validation, loading, serialization checks and ordinary
  evaluation retain their existing behavior.

- Make formally released DMN 1.5 (`20230324`) the sole executable and emitted
  profile; retain explicit best-effort inspection for older documents.
- Add strict schema/profile/model loading, packaged normative schemas, bounded
  secure XML handling, and stable public diagnostics.
- Replace sibling scanning with declared, confined file imports and explicit
  in-memory import maps/resolvers.
- Centralize definitions/local FEEL language inheritance and preserve omitted
  declarations in the normalized model.
- Add capability-specific validation and decision-service evaluator options.
- Isolate trusted external functions from model input, define built-in
  precedence, and redact host failures.
- Publish the conformance contract and construct capability ledger.

## 0.2.0 - 2026-07-19

- Add deterministic DMN 1.4 XML encoding through `Boxic.DMN.encode_xml/2`.
- Add structured serialization preflight errors and explicit rejection of
  version-mismatched or lossy loaded models.
- Retain the source DMN profile, import declarations, and serialization
  fidelity on normalized models.
- Preserve semantically significant FEEL text whitespace during loading.
- Add immutable, ID-based decision-table authoring operations for cells, rules,
  inputs, outputs, ordering, and hit policies.
- Validate focused generated-document fixtures against the vendored official
  DMN 1.4 schema.
- Add generated-model, injection, XML-code-point, bounded-error, atom-safety,
  deep-recursion, and standalone large-table performance coverage.
- Audit all 69 distinct models in the implemented TCK writer profile: all 69
  are explicitly rejected for their newer DMN namespace, with zero writer
  failures or implicit version conversions.

## 0.1.0 - 2026-07-18

- Initial public release.
- Load and normalize DMN 1.4 XML models.
- Validate model structure, types, and references.
- Evaluate decisions, decision tables, boxed expressions, business knowledge
  models, imports, and decision services.
- Validate against DMN TCK revision
  `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`.
- Pass all 1,485 cases in the pinned DMN TCK profile.
