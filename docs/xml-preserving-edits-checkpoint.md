# XML-preserving editing checkpoint

Date: 2026-10-26. Branch: `improve/xml-preserving-edits`.
Review base: accepted expression-validation commit `0489c9c`.

## Scope and compatibility

This phase adds one bounded raw-XML editing operation. The
[API/preservation design](xml-preserving-edits.md) was recorded before
implementation and refined to include a direct-decision-literal selector needed
by the original qualification documents. No original expression ID is fabricated.

The preserved source baseline remains upstream
`8c1706fadd89aa328d56c39e86edd49708876479`, with provenance commit `b9ef13d` and
validation commit `0489c9c`. Runtime/schema source was reconciled against Hex
DMN 0.3.0 / FEEL 0.2.0 at the accepted checkpoint. The fork's differing package
version/dependency metadata is unchanged; see
[the exact provenance report](qualified-package-baseline.md).

No evaluator, hit-policy, normalized Model, loader, existing writer or dependency
configuration was changed. The ordinary evaluation and writer return shapes are
unchanged. A model reloaded from edited XML can still correctly refuse
`encode_xml` with `:lossy_serialization`. The new API retains source XML rather
than weakening that fidelity protection.

No persistence, Tools, Composer/UI, traces, new XML package, package release,
push or PR creation is included. Wedge's source, committed pins and unrelated
work remain untouched. Its original qualification files are read-only inputs to
an isolated path-dependency harness.

Implementation is in a separate worktree at
`/private/tmp/boxic-xml-preserving-edits`, attached to the fork in
`/Users/pg/Documents/Code/projects/boxic`. The projects checkout stays on the
accepted validation branch, and its untracked AGENTS.md remains uncommitted.
Temporary dependency/build symlinks are not part of this change.

## Public API

```elixir
Boxic.DMN.edit_xml(xml, %{element_id: "expression_id", text: "quantity * 12"})

# A real decision ID can locate its single direct literal without a literal ID.
Boxic.DMN.edit_xml(xml, %{decision_id: "price", text: "quantity * 12"})

Boxic.DMN.edit_xml(xml, %{
  table_id: "table", rule_id: "adult", input_id: "age_clause", text: ">= 21"
})

Boxic.DMN.edit_xml(xml, %{
  table_id: "table", rule_id: "adult", output_id: "result", text: "\"approved\""
}, imports: namespace_to_source_map)
# => {:ok, revised_xml} | {:error, diagnostics_or_existing_load_error}
```

One immutable call changes one existing character-data payload. Expression and
allowed-value elements need their own real IDs, except the explicit direct
decision-literal form. Table cells can lack IDs: actual table/rule/clause IDs
select the corresponding column in the existing table. No positional ID escapes
the API. Missing/ambiguous IDs, wrong relationships, unsupported target kinds and
invalid request/options return explicit diagnostics. ID errors identify the ID;
unsupported payload errors identify its XML position. FEEL syntax errors retain
the accepted validator's model/position paths and underlying parser diagnostics.

Supported expression paths follow the existing loader: decision/BKM literals,
nested contexts/functions/invocations/bindings/relations/lists/conditional/filter/
iterator positions, table inputs/conditions/outputs/defaults and allowed-value
tests, including recursive type components. Only existing text can change.
Source XML must pass strict loading; revised XML must pass strict loading/schema
and whole-model evaluation-capability syntax validation. No business inputs or
model evaluation are required for an edit. Runtime success is not promised.

## Preservation evidence and explicit refusals

The implementation uses the installed OTP xmerl DOM/parser/export APIs. A closed
DMN-namespace traversal limits editable positions; foreign lookalikes and opaque
extension descendants are not targets. The full admitted document is retained,
not rebuilt from the normalized model. Parser callbacks retain declaration
metadata that xmerl otherwise omits. Exported XML is reparsed and compared against
the expected edited tree, with an explicit failure if protected content changes.
There is no regex-based XML edit, second evaluator or custom XML serialization
framework.

Measured coverage:

- Descriptions, text/table/rule annotations, default and prefixed DMN namespaces,
  namespace declarations/references, DMNDI shape IDs/bounds, admitted foreign
  extension elements/attributes, Unicode/escaping, and comments before/after the
  document root survive actual text edits. An opaque foreign literal containing
  `if )` remains opaque and unchanged, and cannot be edited as executable FEEL.
- Explicit `standalone="yes"` and `"no"`, absent declarations and declarations
  with omitted encoding are covered. Output uses UTF-8 XML 1.0; lexical encoding
  spelling, attribute order, quote style, CDATA boundaries and entity spelling are
  not byte-fidelity promises. Decoded character data and namespace semantics are
  protected.
- All **10 original selected TCK documents** that the normalized writer refuses
  can undergo a supported stable-ID text edit without losing their XML content.
  The committed test independently compares the resulting XML tree, reloads it,
  checks supported syntax and confirms the existing writer still refuses it.
- The isolated Wedge harness evaluates the originals and edited/reloaded versions
  for **24 selected TCK cases**, with exact result equality between those two
  executions. These preservation/equivalence edits deliberately retain the
  selected text's value. Separate native invoice/refund and table-boundary tests
  actually change values and verify the resulting business outputs.

Unknown XML names/prefixes retain the existing bounded-inspection rejection.
Processing instructions are explicitly refused before DOM parsing because
xmerl's exporter drops them. DTD/entities remain forbidden. Non-UTF-8/XML-1.0
declarations are refused. A selected text payload containing comments/other
markup is refused rather than moving or dropping those children; comments
elsewhere are retained. Missing text is not created. Structural editing,
arbitrary vendor vocabularies and unsupported executable constructs are outside
this API. Preservation does not grant opaque content executable meaning.

These boundaries avoid a loader/model/writer redesign. Supporting arbitrary
extension vocabularies would require a separately reviewed parser/atom-safety
boundary. The normalized writer's existing refusal remains the appropriate
answer for unsupported regeneration paths.

## Verification

Actual runtime: Elixir **1.20.4-otp-28**, OTP **28.5.0.8**, macOS ARM64.
Repository lock: Decimal **3.1.1**, tz **0.28.2**. Isolated Wedge harness:
Decimal **3.2.0**, tz **0.28.4**, path dependencies on this worktree. No lock or
version pin changed. Repository .tool-versions specifies Elixir 1.20.0/OTP 29.0.1;
that exact combination and Linux/release execution remain unverified locally.

Commands, with the actual installed runtime first on PATH:

```sh
export PATH=/Users/pg/.asdf/installs/elixir/1.20.4-otp-28/bin:/Users/pg/.asdf/installs/erlang/28.5.0.8/bin:$PATH
mix format --check-formatted
mix compile --warnings-as-errors
mix quality
mix test
mix test apps/boxic_dmn/test/xml_editor_test.exs
mix tck --suite dmn --profile implemented
git diff --check
```

| Check | Evidence |
| --- | --- |
| Editor regression suite | **15 passed**, including a 17-position nested-expression matrix, BKM body, recursive type tests, all ten fidelity-loss models, imports and negative cases |
| Full umbrella suite | **175 passed**: FEEL 36, DMN 116, TCK tooling 23 |
| Quality gate | Formatting, strict compilation, strict Credo and Dialyzer passed; no suppressions |
| Implemented FEEL TCK profile | **2,042 passed**, 18 explicit Java external-function exclusions |
| Implemented DMN TCK profile | **1,485 passed**, no failed/error/unsupported/missing results |
| Wedge isolated engine tests | **26 passed**, retaining the accepted checkpoint's one updated preflight-gap assertion |
| Wedge edited native fixtures | Invoice output changed to `review_after_edit`; refund eligibility changed to false, both reloaded/evaluated successfully |
| Edited selected-TCK equivalence | **24 exact comparisons passed across 10 models** |

TCK revision remains **`a162739daee85fb28e9d3bec2f306505992dae0f`**. The ten
groups are `0001-input-data-string`, `0002-input-data-number`,
`0003-input-data-string-allowed-values`, `0004-simpletable-U`,
`0008-LX-arithmetic`, `0010-multi-output-U`, `0114-min-collect-hitpolicy`,
`0115-sum-collect-hitpolicy`, `0116-count-collect-hitpolicy` and
`0119-multi-collect-hitpolicy`. No vendored TCK file was changed. The implemented
profiles and selected documents do not establish full conformance/certification.

The isolated harness is `/private/tmp/boxic-wedge-xml-checkpoint`. Its Mix project
points at this worktree's two applications; the already-existing
`BOXIC_DMN_HEX_BUILD=1` dependency branch is used. It reads the unchanged Wedge
qualification helper/runner and two engine-only ExUnit suites, with the accepted
temporary invalid-syntax assertion correction described in the previous
checkpoint. The edited-TCK probe compares raw evaluation results directly; it
does not normalize numeric/null results or alter fixtures/checksums.

```sh
cd /private/tmp/boxic-wedge-xml-checkpoint
BOXIC_DMN_HEX_BUILD=1 MIX_ENV=test mix run probe.exs
BOXIC_DMN_HEX_BUILD=1 MIX_ENV=test mix run edit_probe.exs
```

Private command outputs are under `/private/tmp/boxic-xml-*.log`; the handoff
full-suite and quality runs use separate files. Early fixture/callback mistakes
were corrected, rather than changing library validation or weakening assertions.
Final scope checks confirm no evaluator, dependency, Wedge or vendored-corpus diff.

## Remaining limitations

This is one-text-payload editing of the admitted profile, not arbitrary-model
authoring, byte-for-byte export or a new safety sandbox. Original XML remains the
appropriate retained source. Full-document parsing/export and existing schema
validation run for each edit; no latency/concurrency or large-document benchmark
is claimed. Existing 5 MB/depth/node checks do not establish pre-allocation heap
containment or a hard wall-time bound. Replacement data must also fit the
revised document's existing limits; no new general resource policy was added.

Qualification's independent arithmetic/containment gaps are unchanged: caller
Decimal precision/rounding affects arithmetic; default half_up and broader
numeric range semantics remain unresolved; observed no-match COLLECT returns
nil. Unknown timeout/max-step evaluation options do not impose budgets, and the
xmllint subprocess has no qualified timeout/cancellation contract. The repository
lock's existing Decimal advisory is not resolved by this editing change.

Tracing remains absent and deferred to its own API/design/equivalence checkpoint.
No expression is re-evaluated to infer tracing, and no semantic correction is
hidden in XML editing.

## Prepared upstream PR description

**Title:** Add bounded ID-based XML-preserving expression edits

Imported DMN with descriptions, annotations or diagram/extension content can
evaluate successfully while the normalized writer correctly refuses regeneration
because its representation is lossy. Add `edit_xml/3` to change one supported
expression/table-cell text directly in original XML through real source IDs,
without weakening existing writer fidelity checks.

Use the existing OTP xmerl document APIs, retain admitted surrounding XML, reject
unsupported targets/content explicitly, then strictly reload, syntax-validate and
verify the resulting document. Scope includes nested supported expressions,
table conditions/outputs/defaults and allowed values; it excludes structural or
arbitrary-vocabulary editing. Ordinary evaluation, dependency pins and tracing
remain unchanged. The API documentation declares semantic versus byte fidelity
and explicit processing-instruction/payload restrictions.

Validation: 175 ExUnit tests; strict compilation, formatting, Credo and Dialyzer;
2,042 implemented FEEL TCK passes with 18 explicit Java exclusions; 1,485
implemented DMN TCK passes. All ten selected fidelity-loss documents retain XML
through edits, with 24 exact original/edited evaluation comparisons and changed
native fixture outputs. TCK revision `a162739daee85fb28e9d3bec2f306505992dae0f`;
selected-scope evidence, not certification.

Review this change above `0489c9c` after the accepted provenance/validation work;
do not attribute the earlier upstream reconciliation history to this PR. No push,
publication or PR was performed. Stop here for editing review before tracing.
