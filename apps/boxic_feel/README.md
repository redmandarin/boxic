# Boxic FEEL

Boxic FEEL is a native Elixir parser and evaluator for the Friendly Enough
Expression Language defined by DMN. It can be used independently of
`boxic_dmn`.

## Installation

Add `boxic_feel` to `mix.exs`:

```elixir
def deps do
  [
    {:boxic_feel, "~> 0.1.0"}
  ]
end
```

## Quick start

```elixir
context = %{
  "price" => Decimal.new("12.50"),
  "quantity" => Decimal.new("2")
}

{:ok, total} = Boxic.FEEL.evaluate("price * quantity", context)
```

`Boxic.FEEL.parse/1` returns the public AST without evaluating it.
`Boxic.FEEL.evaluate_ast/2` evaluates a previously parsed AST, and
`Boxic.FEEL.evaluate_unary_test/3` evaluates a DMN unary test against a value.
All public entry points return `{:ok, value}` or
`{:error, %Boxic.FEEL.Error{}}`.

## Compatibility

Evaluation of source, ASTs and unary tests uses 34-digit, half-even Decimal
arithmetic independently of the caller's precision, rounding and trap settings.
The caller's complete context is restored on success and failure. Named rounding
functions preserve their own modes. Numeric invalid/overflow results become
local FEEL nulls; unrelated failures retain their existing behavior.
See [the scoped arithmetic contract](../../docs/scoped-feel-arithmetic.md).
Literal/input admission, exponent endpoints and existing float-backed functions
remain separate numeric-conformance concerns.

Against the vendored official DMN Technology Compatibility Kit revision
`0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`, Boxic passes 2,042 of the 2,060
selected FEEL cases. The remaining 18 are Java external-function integration
cases and are reported explicitly as unsupported. Compatibility on the
supported scope is 100%.

## Elixir external functions

Trusted application code can expose an allowlisted set of Elixir functions to
FEEL. Model text receives callable names only: it cannot construct module names,
atoms, or arbitrary MFA tuples.

This is Boxic's platform-native replacement for DMN Java external functions.
Both mechanisms let decisions call trusted host-language code, but the Elixir
registry targets the BEAM rather than JVM classes and reflection. The official
Java-specific TCK group remains unsupported because an Elixir call is not Java
interoperability.

### Define host functions

External functions are ordinary public Elixir functions. For example:

```elixir
defmodule MyApp.Pricing do
  def maximum(left, right), do: max(left, right)

  # A variadic FEEL tail arrives as a list in the final Elixir argument.
  def join(first, rest), do: Enum.join([first | rest], " ")
end
```

### Create an allowlisted registry

Define a registry with the compile-time DSL:

```elixir
defmodule MyApp.DecisionFunctions do
  use Boxic.FEEL.ExternalFunctions

  external "maximum", {MyApp.Pricing, :maximum},
    parameters: [:integer, :integer],
    returns: :number

  external "joinWords", {MyApp.Pricing, :join},
    parameters: [:string, {:varargs, :string}],
    returns: :string
end
```

Only functions present in this registry are exposed. The DMN model never
receives `{module, function}` values and cannot turn strings into modules or
atoms.

### Boundary types

The `parameters` and `returns` options control conversion at the trusted host
boundary:

| Type | FEEL side | Elixir side |
| ---- | --------- | ----------- |
| `:feel` | Any supported FEEL value | Unchanged Boxic value |
| `:number` | Number | `Decimal` |
| `:integer` | Integral number | Integer; returned integers become `Decimal` |
| `:float` | Number | Float; returned floats become `Decimal` |
| `:string` | String | UTF-8 binary |
| `:char` | One-codepoint string | Unicode codepoint integer |
| `:boolean` | Boolean | Boolean |

An empty `parameters` list performs no argument conversion or arity check. A
final `{:varargs, type}` accepts any additional FEEL arguments, converts them,
and passes them as a list in the final Elixir argument.

### Call from FEEL

Supply the registry through the evaluator environment:

```elixir
opts = [external_functions: MyApp.DecisionFunctions]

{:ok, maximum} = Boxic.FEEL.evaluate("maximum(123, 456)", %{}, opts)
{:ok, "foo bar baz"} =
  Boxic.FEEL.evaluate(~S|joinWords("foo", "bar", "baz")|, %{}, opts)
```

The registry is not merged into ordinary FEEL input data. Built-ins take
precedence by default. Applications that deliberately replace a built-in for a
particular trusted evaluation must pass
`external_function_precedence: :registered`.

### Call from DMN

The DMN literal expression calls the registered name normally:

```xml
<decision id="price" name="Price">
  <literalExpression>
    <text>maximum(requested price, price ceiling)</text>
  </literalExpression>
</decision>
```

Supply the registry separately when evaluating the trusted model. The registry
is host configuration and is not encoded in DMN XML:

```elixir
Boxic.DMN.evaluate(model, "Price", inputs,
  external_functions: MyApp.DecisionFunctions
)

Boxic.DMN.evaluate_service(model, "Pricing Service", arguments,
  external_functions: MyApp.DecisionFunctions
)
```

The registry module or an `Boxic.FEEL.ExternalFunctions` registry value may be
passed through `:external_functions`.

### Errors and trust boundary

Invalid arity, argument conversion failures, invalid return values, and
exceptions raised by host code become structured `Boxic.FEEL.Error` values.
External functions execute in the evaluator process, so application code should
keep them deterministic and fast and should add its own timeout or isolation
when calling remote services.

Do not construct registry entries from model content or untrusted strings. The
registry must remain trusted application configuration; this is what prevents
the feature from becoming arbitrary BEAM code execution.

This replacement is a Boxic Elixir extension, not an implementation of
DMN's Java external-function binding. The official Java-specific TCK group is
therefore still selected and explicitly reported as unsupported.

## License

Boxic FEEL is licensed under Apache-2.0. The official TCK corpus and local
compatibility artifacts are not included in the Hex package.

### Qualified numeric and bounded evaluation profile

Decimal 3.2.0 is required and qualified. Numeric literals, AST/context Decimals,
number strings and host results share bounded 34-digit nearest-even admission.
Nonfinite, malformed and out-of-domain admission returns `:invalid_number`;
invalid `number()` conversion returns FEEL null. Numeric spelling/coefficient
limits (8192 bytes/digits, parsed exponent magnitude 20000) are library resource
policies. Exact subnormals down to 1e-6176 are preserved; arithmetic overflow and
inexact underflow return local nulls. The caller's full Decimal context is restored.
Mean has no extra decimal-place rounding; sqrt/stddev use Decimal.sqrt. Explicit
rounding functions retain their modes. These changes do not certify all numerics.

`Boxic.FEEL.Profile.validate(source)` (or with `:unary_tests`) statically enforces
the bounded v1 math capability. exp/log, dynamic function calls/definitions,
callback-taking sort/list-replace and nonliteral/noninteger powers are excluded;
literal integer powers are bounded to magnitude 1024. All branches and deferred
function references are checked. General evaluation of excluded functions remains
legacy behavior, not qualified v1 support.

`Boxic.FEEL.evaluate_bounded(source, inputs, timeout: 1000,
max_heap_words: 8_000_000)` enforces this gate and rejects callable inputs, then
returns `{:ok, ordinary_evaluation_return}` or a boundary error. For other trusted
entry points, `Boxic.FEEL.Execution.run(fn -> ... end, limits)` provides the same
worker containment without adding a capability gate. It does not sandbox host
effects. See that module and the DMN README for heap/deadline responsibilities.
