# Bounded XML-preserving text edits

Design recorded before implementation, against accepted expression-validation
commit `0489c9c` (qualified executable-source baseline `8c1706f`).

## API and boundary

Add `Boxic.DMN.edit_xml(xml, edit, opts \\ [])`, returning
`{:ok, revised_xml} | {:error, diagnostics}`. It changes **one existing text
payload**, with four closed request forms:

```elixir
Boxic.DMN.edit_xml(xml, %{element_id: "price_expression", text: "quantity * 12"})
Boxic.DMN.edit_xml(xml, %{decision_id: "price", text: "quantity * 12"})
Boxic.DMN.edit_xml(xml, %{
  table_id: "pricing", rule_id: "standard", input_id: "quantity", text: "> 10"
})
Boxic.DMN.edit_xml(xml, %{
  table_id: "pricing", rule_id: "standard", output_id: "price", text: "120"
})
```

The first form requires an actual XML ID on a supported literal expression,
table input expression, input/output entry, existing default, or allowed-values
element. Nested supported expression positions and item-component allowed
values are included. The decision form selects exactly one direct literal
expression through its real owning decision ID, without assigning a synthetic
expression ID. This covers the qualification documents whose literal has no ID.
It cannot edit arbitrary `<text>` nodes, annotations or
opaque extension expressions. Table forms resolve the actual table, rule and
input/output clause by their IDs, then locate that clause's cell by its current
column position. The positional lookup is internal; no synthetic ID is exposed
or persisted. Missing/ambiguous IDs, conflicting/unknown fields, wrong parent
relationships and unsupported targets fail explicitly. No structural edits,
missing text creation, name/ID changes, batch protocol or optimistic revision
mechanism are introduced.

The selected `<text>` must contain character data only (including CDATA).
Comments or other child markup inside that particular payload are explicitly
refused rather than moved or dropped. Comments elsewhere are preserved.

Only `imports: namespace_to_source_map` is accepted, reusing the existing loader
for models with explicit imports. Imported documents are not modified. No new
ambient file/network resolution or resolver callback is introduced. XML and
replacement text must be UTF-8/XML 1.0 text. Existing size/depth/node/name bounds
still apply; there is no new hard CPU/heap/deadline guarantee.

## Preservation and validation

The current Writer rebuilds XML from normalized values, gated by serialization
fidelity. It cannot retain all descriptions, annotations, DMNDI or extensions.
Its APIs and refusal behavior stay unchanged. The new operation therefore takes
original XML, not a potentially stale normalized Model. It uses the installed
OTP xmerl document parser/exporter rather than reconstructing XML from the Model
or using regex substitutions. Parsing the complete document retains comments
outside the root as well as child nodes, prefixes and attributes.

Preservation covers the existing loader-admitted DMN 1.5 XML vocabulary and
namespace prefixes: descriptions, standard annotations, DMNDI, and admitted
opaque extension content/attributes. Unknown extension names/prefixes remain
rejected by the existing bounded name guard; supporting arbitrary vocabularies
safely would require a separately reviewed parser boundary. Preservation does
not grant those elements executable meaning.

OTP xmerl's exporter discards processing instructions, so documents containing
them are explicitly refused before DOM parsing. DTD/entities remain forbidden.
Only UTF-8 XML 1.0 is admitted by this API. Serialization preserves decoded text,
attributes, namespace bindings, comments and node order, not original byte layout,
quote style, entity spellings, CDATA boundaries or declaration encoding spelling.
The standalone declaration flag is retained. A semantic-tree comparison after
serialization refuses an output if xmerl cannot preserve the expected document
(for example attribute whitespace/character-reference round-trip differences).
This is a fail-closed check, not a custom XML serializer or general XML editor.

The source must pass existing strict loading/schema/model checks. Revised output
is reloaded, schema-checked and validated for evaluation, including the accepted
whole-model supported-expression syntax checks. No business input or evaluation
is needed. This allows repairing a syntax-invalid target in otherwise structurally
valid XML, but refuses remaining invalid/unsupported executable expressions.
Syntax success does not prove runtime success. Loaded revised models may still
be lossy for `encode_xml`; that refusal is deliberately preserved.

## Implementation and regression plan

One cohesive `Boxic.DMN.XML.Editor` owns selection, document mutation and
preservation verification. `Boxic.DMN` exposes the public operation. No Model
storage redesign, writer rewrite, new dependency or evaluator change is needed.

Regression cases cover actual evaluation changes; original/revised XML metadata;
namespace and extension lookalikes; missing/duplicate IDs; column relationships;
defaults/unary tests; malformed untouched expressions; safety limits; and existing
writer refusals. Include the pinned TCK documents that previously refused rewritten
export, testing exact edits where stable source IDs exist. Re-run real Wedge
qualification through an isolated harness, without changing Wedge's pins. Tracing
remains a separate checkpoint.
