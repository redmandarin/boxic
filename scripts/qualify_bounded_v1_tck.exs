# Qualification tooling: selected pinned cases, never a conformance claim.
# Run: MIX_ENV=test mix run --no-start scripts/qualify_bounded_v1_tck.exs
{:ok, _applications} = Application.ensure_all_started(:boxic_dmn)
alias Boxic.DMN
alias Boxic.DMN.TCK.{Comparator, Loader, ModelLoader}

groups =
  DMN.TCK.profile_groups("feel", "implemented") ++ DMN.TCK.profile_groups("dmn", "implemented")

cases = Loader.load_all() |> Enum.filter(&(&1.group in groups))
if cases == [], do: raise("qualification selection must not be empty")

evaluate = fn model, test_case, traced ->
  service? = test_case.metadata[:case_type] == "decisionService"
  name = if service?, do: test_case.metadata[:invocable_name], else: test_case.decision_name
  opts = [profile: :bounded_v1]

  result =
    case {service?, traced} do
      {false, false} -> DMN.evaluate(model, name, test_case.inputs, opts)
      {false, true} -> DMN.evaluate_with_trace(model, name, test_case.inputs, opts)
      {true, false} -> DMN.evaluate_service(model, name, test_case.inputs, opts)
      {true, true} -> DMN.evaluate_service_with_trace(model, name, test_case.inputs, opts)
    end

  case result do
    {status, value, %DMN.Trace{}} -> {status, value}
    {status, value} -> {status, value}
  end
end

rows =
  cases
  |> Enum.group_by(& &1.model_path)
  |> Enum.sort()
  |> Enum.flat_map(fn {path, model_cases} ->
    {:ok, model} = ModelLoader.load(path)

    case DMN.validate(model, for: :evaluation, profile: :bounded_v1) do
      :ok ->
        Enum.map(model_cases, fn test_case ->
          ordinary = evaluate.(model, test_case, false)
          traced = evaluate.(model, test_case, true)

          expected_matches =
            case ordinary do
              {:ok, value} ->
                value =
                  if test_case.metadata[:case_type] == "decisionService" and is_map(value),
                    do: Map.get(value, test_case.decision_name, value),
                    else: value

                Comparator.semantic_equal?(value, test_case.expected)

              {:error, _reason} ->
                test_case.expect_error
            end

          runtime_rejection =
            case ordinary do
              {:error, %Boxic.FEEL.Error{code: code}}
              when code in [:unsupported_profile, :execution_limit_exceeded] ->
                code

              _ ->
                nil
            end

          %{
            group: test_case.group,
            id: test_case.id,
            decision: test_case.decision_name,
            status:
              cond do
                ordinary !== traced -> :failed
                not is_nil(runtime_rejection) -> :runtime_excluded
                expected_matches -> :passed
                true -> :failed
              end,
            runtime_rejection: runtime_rejection,
            exact_trace_equivalence: ordinary === traced
          }
        end)

      {:error, diagnostics} ->
        policy_exclusion? = Enum.any?(diagnostics, &(&1.code == :unsupported_profile))

        negative_decisions =
          for test_case <- model_cases, test_case.expect_error, do: test_case.decision_name

        negative_fixture? =
          Enum.all?(diagnostics, fn diagnostic ->
            case diagnostic.path do
              [:decisions, id | _position] ->
                diagnostic.code == :invalid_feel_syntax and
                  model.decisions[id].name in negative_decisions

              _ ->
                false
            end
          end)

        Enum.map(model_cases, fn test_case ->
          %{
            group: test_case.group,
            id: test_case.id,
            decision: test_case.decision_name,
            status:
              cond do
                policy_exclusion? -> :excluded
                negative_fixture? -> :rejected_negative_fixture
                true -> :failed_validation
              end,
            diagnostic_codes: Enum.uniq(Enum.map(diagnostics, & &1.code)),
            diagnostic_paths: Enum.map(diagnostics, & &1.path)
          }
        end)
    end
  end)

report = %{
  revision: File.read!(Path.expand("../vendor/dmn-tck/PINNED_COMMIT", __DIR__)) |> String.trim(),
  profile: "bounded_v1",
  decimal: to_string(Application.spec(:decimal, :vsn)),
  elixir: System.version(),
  otp: to_string(:erlang.system_info(:otp_release)),
  source_revision: elem(System.cmd("git", ["rev-parse", "HEAD"]), 0) |> String.trim(),
  selected_legacy_implemented_cases: length(cases),
  summary: Enum.frequencies_by(rows, & &1.status),
  by_group:
    rows
    |> Enum.group_by(& &1.group)
    |> Map.new(fn {group, rows} ->
      {group, Enum.frequencies_by(rows, & &1.status)}
    end),
  runtime_exclusions: Enum.filter(rows, &(&1.status == :runtime_excluded)),
  rejected_negative_fixtures: Enum.filter(rows, &(&1.status == :rejected_negative_fixture)),
  failures:
    Enum.filter(
      rows,
      &(&1.status not in [:passed, :excluded, :runtime_excluded, :rejected_negative_fixture])
    )
}

IO.puts(Jason.encode!(report, pretty: true))
if report.failures != [], do: System.halt(1)
