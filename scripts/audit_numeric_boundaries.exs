# Observation tooling, not a conformance gate or a new input-admission path.
# Run with: MIX_ENV=test mix run --no-start scripts/audit_numeric_boundaries.exs
{:ok, _applications} = Application.ensure_all_started(:boxic_dmn)

{:ok, model} =
  Boxic.DMN.load_xml("""
  <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/" id="audit" name="Audit" namespace="urn:arithmetic-audit">
    <inputData id="x" name="x"><variable name="x" typeRef="number"/></inputData>
    <decision id="value" name="Value"><informationRequirement><requiredInput href="#x"/></informationRequirement><literalExpression><text>x</text></literalExpression></decision>
  </definitions>
  """)

oversize = Decimal.new(1, 12_345_678_901_234_567_890_123_456_789_012_345, 0)
smallest = Decimal.new(1, 1, -6_176)
largest = Decimal.new(1, String.to_integer(String.duplicate("9", 34)), 6_111)

observations = [
  {"literal_35_digits_parse", fn -> Boxic.FEEL.parse("12345678901234567890123456789012345") end},
  {"literal_35_digits_evaluate",
   fn -> Boxic.FEEL.evaluate("12345678901234567890123456789012345") end},
  {"trusted_ast_35_digits", fn -> Boxic.FEEL.evaluate_ast({:literal, oversize}, %{}) end},
  {"trusted_context_35_digits", fn -> Boxic.FEEL.evaluate("x", %{"x" => oversize}) end},
  {"trusted_context_35_digits_plus_zero",
   fn -> Boxic.FEEL.evaluate("x + 0", %{"x" => oversize}) end},
  {"dmn_decimal_struct_35_digits",
   fn -> Boxic.DMN.evaluate(model, "Value", %{"x" => oversize}) end},
  {"dmn_number_string_35_digits",
   fn -> Boxic.DMN.evaluate(model, "Value", %{"x" => "12345678901234567890123456789012345"}) end},
  {"literal_max_adjusted_exponent", fn -> Boxic.FEEL.evaluate("1e6144") end},
  {"literal_exponent_above_max", fn -> Boxic.FEEL.evaluate("1e6145") end},
  {"literal_min_subnormal", fn -> Boxic.FEEL.evaluate("1e-6176") end},
  {"trusted_min_subnormal", fn -> Boxic.FEEL.evaluate("x", %{"x" => smallest}) end},
  {"trusted_min_subnormal_times_one", fn -> Boxic.FEEL.evaluate("x * 1", %{"x" => smallest}) end},
  {"normal_to_subnormal_division",
   fn -> Boxic.FEEL.evaluate("x / 10", %{"x" => Decimal.new(1, 1, -6_143)}) end},
  {"below_min_subnormal_division", fn -> Boxic.FEEL.evaluate("x / 10", %{"x" => smallest}) end},
  {"largest_finite_times_one", fn -> Boxic.FEEL.evaluate("x * 1", %{"x" => largest}) end},
  {"largest_finite_times_ten", fn -> Boxic.FEEL.evaluate("x * 10", %{"x" => largest}) end},
  {"mean_third_precision", fn -> Boxic.FEEL.evaluate("mean([1, 0, 0])") end},
  {"exp_one_precision", fn -> Boxic.FEEL.evaluate("exp(1)") end},
  {"sqrt_two_precision", fn -> Boxic.FEEL.evaluate("sqrt(2)") end},
  {"sqrt_large_float_conversion",
   fn -> Boxic.FEEL.evaluate("sqrt(x)", %{"x" => Decimal.new(1, 1, 6_000)}) end},
  {"trusted_context_nan", fn -> Boxic.FEEL.evaluate("x", %{"x" => Decimal.new("NaN")}) end},
  {"dmn_number_string_nan", fn -> Boxic.DMN.evaluate(model, "Value", %{"x" => "NaN"}) end}
]

describe = fn
  nil ->
    nil

  %Decimal{} = value ->
    %{sign: value.sign, coefficient: to_string(value.coef), exponent: value.exp}

  value ->
    inspect(value, limit: 10)
end

rows =
  Enum.map(observations, fn {label, callback} ->
    before = Decimal.Context.get()

    outcome =
      try do
        case callback.() do
          {:ok, {:literal, %Decimal{} = value}} -> %{status: "parsed", value: describe.(value)}
          {:ok, value} -> %{status: "ok", value: describe.(value)}
          {:error, error} -> %{status: "error", error: inspect(error, limit: 10)}
        end
      rescue
        exception ->
          %{
            status: "raised",
            exception: inspect(exception.__struct__),
            message: Exception.message(exception)
          }
      end

    Map.merge(outcome, %{label: label, caller_context_restored: Decimal.Context.get() === before})
  end)

IO.puts(
  Jason.encode!(
    %{
      decimal: to_string(Application.spec(:decimal, :vsn)),
      elixir: System.version(),
      observations: rows
    },
    pretty: true
  )
)
