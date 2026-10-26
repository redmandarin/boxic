# Supported-expression validation

Boxic targets DMN 1.5. Explicit capability validation now parses every supported
expression position, including work ordinary evaluation may skip:

```elixir
with {:ok, model} <- Boxic.DMN.load_xml(xml),
     :ok <- Boxic.DMN.validate(model, for: :evaluation) do
  Boxic.DMN.evaluate(model, "Price", inputs)
end
```

`validate(model, for: :authoring)` performs the same syntax checks alongside
its existing model checks. No test inputs, function registry or evaluation is
required. Existing return shapes remain `:ok | {:error, diagnostics}`.

## Coverage

| Supported position | Grammar |
| --- | --- |
| Decision and BKM literal text | FEEL expression |
| Boxed context entries, including the unnamed result | Recursively validate contained expression |
| Boxed function body and BKM encapsulated logic | Recursively validate body, with parameter declarations |
| Invocation function and every parameter binding | Recursively validate contained expression |
| Every relation row/cell and boxed list item | Recursively validate contained expression |
| Boxed conditional condition, then and else | Recursively validate all three expressions |
| Boxed filter source and match | Recursively validate both expressions |
| Boxed for/some/every source and body | Recursively validate both expressions |
| Decision-table input expressions | FEEL expression |
| Every rule input entry | FEEL unary tests |
| Every rule output entry | FEEL expression |
| Every output default | FEEL expression |
| Input/output clause allowed values | FEEL unary tests |
| Item-definition and recursive component allowed values | FEEL unary tests |

Absent optional allowed values/defaults are skipped. Missing required expression
text remains a structural validation error. Coverage follows the normalized
expression types supported by the engine; it does not infer executable meaning
for arbitrary XML extensions, annotations or unrepresented constructs.

Expression parsing reuses `Boxic.FEEL.parse/1`, including its AST validation.
The added `Boxic.FEEL.validate_unary_tests/1` reuses the tokenizer and expression
parser with the unary-test entry grammar: dash, positive tests, comma-separated
alternatives and negation. Nested function/context/list commas remain inside
their expressions. Validation examines all alternatives, without short circuiting
on a matching test or requiring a candidate value.

```elixir
Boxic.FEEL.validate_unary_tests("< 18, >= 65") # => :ok
Boxic.FEEL.validate_unary_tests("not(< 18, >= 65)") # => :ok
Boxic.FEEL.validate_unary_tests("1, if )") # => {:error, %Boxic.FEEL.Error{...}}
```

The grammar boundary follows [DMN 1.5](https://www.omg.org/spec/DMN/1.5/PDF),
10.3.1.2, especially rules 7–16. Boxed scope declarations follow 7.3.1's
Expression discussion and 10.2/10.3. Syntax checking does not create an alternate
evaluator or require changing runtime unary-test semantics.

## Names and scope

Static parsing uses declaration names rather than fabricated context values.
It shares execution's name-spelling normalization, preserving string literals.
Names come from model declarations, import aliases and declared type components;
boxed contexts add previous entries in order, functions add parameters, and
iterators add their variable only for the body. Result context keys and relation
columns inform boxed collection bindings without evaluating their source.

This is syntax validation, not a static name-resolution or type checker.
Unknown single identifiers and host calls may parse successfully. Arbitrary
runtime-created context keys, missing type information and name forms outside
the existing parser/normalizer's supported grammar are not given new execution
semantics. The TCK `0089-nested-inputdata-imports` case specifically protects
multiword import aliases. Recursive type references are bounded by a visited
type list during name discovery.

## Diagnostics and compatibility

A malformed supported expression such as `if )` produces a `Diagnostic` with
code `:invalid_feel_syntax`, category `:feel`, original text, grammar and underlying
`Boxic.FEEL.Error` in `cause`. For example:

```elixir
%Boxic.DMN.Diagnostic{
  code: :invalid_feel_syntax,
  category: :feel,
  message: "Invalid FEEL expression: invalid if-expression",
  path: [:decisions, "price", :expression, :rules, "rule_2", :output_entries, 0],
  details: %{grammar: :expression, text: "if )"}
}
```

Decision/BKM map keys and available clause/rule/context-entry IDs identify the
owner. Collection positions without a source ID use zero-based indices. These
indices describe positions; they are not invented stable IDs. Diagnostics use
the existing `Diagnostic.to_map/1` conversion. Structural/model errors retain
their existing codes and paths. Unsupported normalized expressions and
non-FEEL languages retain their separate unsupported diagnostics; language text
is not incorrectly parsed as FEEL. Parser rejection describes the supported
grammar, not a proof that a construct is invalid in every OMG FEEL implementation.

The intentional behavior change is stronger explicit evaluation/authoring
validation: text previously accepted by those capability checks may now be
rejected, even in an unused decision, unselected branch, unmatched output or
unused default. Authoring operations that already invoke authoring validation
inherit this stronger check.

`validate/1` remains structural. Strict loading remains XML safety/XSD/profile/
structural validation, and still requires the explicit capability check for
complete supported-expression syntax validation. Serialization/fidelity checks
remain unchanged. Ordinary `evaluate` and `evaluate_service` keep their existing
structural preflight, expression scheduling and result/error shapes. They do not
implicitly perform the new all-expression check or execute previously skipped
work.

Syntax success does not establish input presence, type correctness, allowed-value
membership, host-function availability, arithmetic safety, termination or runtime
success. Name lookup, coercion, data-dependent failures and resource containment
remain separate concerns. This change does not add a Wedge publication API.
