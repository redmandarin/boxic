# Boxic contributor instructions

These instructions apply to the Boxic umbrella repository. Keep the library domain-agnostic, idiomatic Elixir and suitable for upstream contribution. Task prompts define assigned scope; this file does not authorize implementing a roadmap.

## Scope and compatibility

- Inspect existing APIs, modules, tests and repository documentation before designing changes. Follow the existing umbrella application boundaries for FEEL, DMN and TCK tooling.
- Preserve existing public return shapes and behavior unless the assignment explicitly approves a change. Document public APIs, options, errors and compatibility changes with typespecs and examples where useful.
- Keep application concerns outside the engine: no Wedge database schemas, authorization, Tool bindings, publication lifecycle or UI dependencies.
- Preserve unrelated work. Do not push, publish packages or open pull requests unless the task authorizes those actions.
- Establish source provenance before comparing a Git checkout with a published package. Record exact revisions and dependency versions; do not assume version labels prove matching source.

## Simplicity and Elixir readability

- Use the smallest supported implementation with existing library conventions. New modules and abstractions need a concrete production responsibility; avoid speculative registries, generic runners and forwarding wrappers.
- Prefer cohesive modules and domain-named helpers. Do not split code merely to meet arbitrary size or nesting limits.
- Prefer adjacent function clauses for distinct cases, with for linear prerequisites, and small case/if/cond expressions for local choices.
- Match clause-selecting fields in function heads; read other fields in the body. Remove unused arguments and avoid catch-all context structs introduced only to reduce arity.
- Pass complete existing model/decision/rule structs between ordinary domain functions when they represent the operation's subject. IDs and scalar values remain appropriate for public lookup boundaries, expression values and serialization.
- Return meaningful tagged errors near their source. Preserve distinctions between malformed XML, invalid FEEL, unsupported constructs and evaluation failures. Do not hide programming errors with broad rescue clauses or collapse unrelated failures into one generic result.
- Keep operation selection, validation and effects understandable without tracing chains of handle/do_handle helpers. Refactor concrete readability problems within scope; avoid unrelated rewrites.

## Standards and semantics

- Follow the explicitly supported OMG DMN/FEEL version and profile. Cite the relevant specification clause or TCK case when changing semantics; do not invent a simplified decision language.
- Distinguish XML well-formedness, XSD validity, model validation, FEEL syntax validation and runtime evaluation. Do not claim one proves the others.
- Use the correct grammar for FEEL expressions and unary tests. Static validation must not require executing expressions with fabricated business inputs.
- Preserve decimal precision through evaluation and conversion. Verify rounding and numeric context against the supported standard; do not silently route exact values through binary floats or leak process-local context changes.
- Do not silently discard unsupported XML. Declare preservation/editing scope and refuse operations that cannot preserve the required content. Distinguish semantic preservation from byte-for-byte fidelity.
- Optional traces must describe the actual execution, not a second evaluation. Preserve results, errors, ordering and hit-policy semantics; distinguish matched rules, contributing rules and work not evaluated.
- Do not claim complete conformance or certification from selected tests. Report tested scope and limitations precisely.

## Tests and quality

- Exercise real parser, validator, evaluator and serializer behavior. Do not mock internal functions or introduce production switches solely for tests. Keep fixture builders and helpers in test code.
- Add regression tests for changed behavior and failures, with valid counterparts. Test observable semantics rather than private helper arrangement.
- Use isolated temporary files and clean them up. External effects may be substituted only at their external boundary when needed.
- Run repository gates appropriate to the change: mix format --check-formatted, mix compile --warnings-as-errors, mix test, and mix quality before handoff where available. Inspect current aliases first: the root test alias also runs the implemented FEEL TCK profile, and quality includes Credo and Dialyzer.
- Run relevant DMN/FEEL TCK cases for semantic changes and record the suite revision, profile, exclusions and results. Do not weaken assertions to make failures disappear.
- Review the actual diff for API compatibility, readable control flow, cohesive modules and unnecessary mechanisms. Passing tests alone does not establish good design.
- Report commands run, results, unavailable checks, remaining limitations and exact commits. Separate semantic fixes, preservation changes and tracing into reviewable commits when assigned together.
