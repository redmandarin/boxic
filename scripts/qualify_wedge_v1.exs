# Run in an isolated path-dependency harness; never modifies Wedge sources/pins.
# WEDGE_ROOT=/path/to/wedge BOXIC_DMN_HEX_BUILD=1 MIX_ENV=test mix run /path/to/boxic/scripts/qualify_wedge_v1.exs
wedge_root = System.fetch_env!("WEDGE_ROOT")
repository = Path.expand("..", __DIR__)
Application.ensure_all_started(:boxic_dmn)
IO.puts(inspect({:decimal_version, Application.spec(:decimal, :vsn)}))
Code.require_file("#{wedge_root}/tasks/decision_models/02_contracts/qualify.exs")
ExUnit.start()
qualification_path = "#{wedge_root}/test/yv/decision_models/qualification_test.exs"
qualification = File.read!(qualification_path)

former_trace_assertion = ~S"""
    refute Enum.any?(Boxic.DMN.__info__(:functions), fn {name, _} ->
             String.contains?(Atom.to_string(name), "trace")
           end)
"""

new_trace_assertion = ~S"""
    assert function_exported?(Boxic.DMN, :evaluate_with_trace, 4)
    assert function_exported?(Boxic.DMN, :evaluate_service_with_trace, 4)
    assert {:ok, true, trace} = Boxic.DMN.evaluate_with_trace(model, "RefundEligible", Q.refund_inputs())
    assert trace.status == :ok
    assert Enum.any?(trace.events, &(&1.kind == :decision && &1.source_id == "RefundEligible"))
"""

1 = length(String.split(qualification, former_trace_assertion)) - 1

Code.compile_string(
  String.replace(qualification, former_trace_assertion, new_trace_assertion),
  qualification_path
)

path = "#{wedge_root}/test/yv/decision_models/xml_qualification_test.exs"
source = File.read!(path)
old = "assert :ok = Boxic.DMN.validate(model, for: :evaluation)"

replacement =
  "assert {:error, [%{code: :invalid_feel_syntax, category: :feel, path: [:decisions, \"RefundEligible\", :expression, :text]}]} = Boxic.DMN.validate(model, for: :evaluation)"

# Only the obsolete observation of the deliberately fixed gap changes.
1 = length(String.split(source, old)) - 1
source = String.replace(source, old, replacement)

old_precision_assertion =
  ~S|assert Decimal.to_string(third) == "0." <> String.duplicate("3", precision)|

new_precision_assertion = ~S"""
        assert Decimal.to_string(third) == "0." <> String.duplicate("3", 34)
        assert Decimal.Context.get() == %Decimal.Context{precision: precision}
"""

1 = length(String.split(source, old_precision_assertion)) - 1

Code.compile_string(
  String.replace(source, old_precision_assertion, new_precision_assertion),
  path
)

for name <- ["invoice_review", "refund"] do
  :ok = Boxic.DMN.validate(Yv.DecisionModelsQualification.model(name), for: :evaluation)
end

root = "#{wedge_root}/test/fixtures/decision_models/qualification/tck"

for path <- Path.wildcard(root <> "/**/*.dmn") do
  {:ok, model} = path |> File.read!() |> Boxic.DMN.load_xml()
  :ok = Boxic.DMN.validate(model, for: :evaluation)
end

alias Yv.DecisionModelsQualification, as: Q

for {name, entry, inputs} <- [
      {"invoice_review", "ReviewDisposition", Q.invoice_inputs()},
      {"refund", "RefundEligible", Q.refund_inputs()}
    ] do
  model = Q.model(name)
  :ok = Boxic.DMN.validate(model, for: :evaluation, profile: :bounded_v1)
  {:ok, value} = Boxic.DMN.evaluate(model, entry, inputs)
  {:ok, {:ok, ^value}} = Boxic.DMN.evaluate_bounded(model, entry, inputs)
  {:ok, {:ok, ^value, trace}} = Boxic.DMN.evaluate_bounded(model, entry, inputs, trace: true)
  false = trace.truncated
  IO.puts(inspect({:bounded_native_passed, name}))
end

classifications =
  for row <- Q.cases() do
    {:ok, model} = root |> Path.join(row["model"]) |> File.read!() |> Boxic.DMN.load_xml()
    inputs = Q.decode(row["inputs"])
    {:ok, value} = Boxic.DMN.evaluate(model, row["decision"], inputs)
    {:ok, ^value, _trace} = Boxic.DMN.evaluate_with_trace(model, row["decision"], inputs)

    case Boxic.DMN.validate(model, for: :evaluation, profile: :bounded_v1) do
      :ok ->
        {:ok, ^value} = Boxic.DMN.evaluate(model, row["decision"], inputs, profile: :bounded_v1)

        {:ok, ^value, _trace} =
          Boxic.DMN.evaluate_with_trace(model, row["decision"], inputs, profile: :bounded_v1)

        :passed

      {:error, diagnostics} ->
        true = Enum.any?(diagnostics, &(&1.code == :unsupported_profile))
        :excluded_by_profile
    end
  end

IO.puts(inspect({:selected_tck_exact_comparisons, length(Q.cases())}))
IO.puts(inspect({:bounded_selected_tck, Enum.frequencies(classifications)}))

for path <- [
      "apps/boxic_feel/test/arithmetic_context_test.exs",
      "apps/boxic_dmn/test/arithmetic_context_test.exs",
      "apps/boxic_dmn/test/evaluation_trace_test.exs",
      "apps/boxic_feel/test/numeric_admission_test.exs",
      "apps/boxic_dmn/test/numeric_admission_test.exs",
      "apps/boxic_feel/test/mathematics_profile_test.exs",
      "apps/boxic_feel/test/dynamic_power_test.exs",
      "apps/boxic_dmn/test/dynamic_power_test.exs",
      "apps/boxic_feel/test/execution_boundary_test.exs",
      "apps/boxic_dmn/test/containment_test.exs"
    ] do
  Code.require_file(Path.join(repository, path))
end
