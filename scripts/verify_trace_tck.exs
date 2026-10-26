# Run with: MIX_ENV=test mix run --no-start scripts/verify_trace_tck.exs
# This is test tooling, not an alternate production evaluation path.
{:ok, _applications} = Application.ensure_all_started(:boxic_dmn)

groups = Boxic.DMN.TCK.profile_groups("dmn", "implemented")
cases = Boxic.DMN.TCK.Loader.load_all() |> Enum.filter(&(&1.group in groups))

capture = fn callback ->
  try do
    {:return, callback.()}
  rescue
    exception -> {:raised, exception.__struct__, Exception.message(exception)}
  catch
    kind, reason -> {kind, reason}
  end
end

evaluate = fn model, test_case, traced ->
  service? = test_case.metadata[:case_type] == "decisionService"

  operation =
    case {service?, traced} do
      {false, false} -> &Boxic.DMN.evaluate/3
      {false, true} -> &Boxic.DMN.evaluate_with_trace/3
      {true, false} -> &Boxic.DMN.evaluate_service/3
      {true, true} -> &Boxic.DMN.evaluate_service_with_trace/3
    end

  name = if service?, do: test_case.metadata[:invocable_name], else: test_case.decision_name

  capture.(fn ->
    case operation.(model, name, test_case.inputs) do
      {status, value, %Boxic.DMN.Trace{}} -> {status, value}
      {status, value} -> {status, value}
    end
  end)
end

failures =
  cases
  |> Enum.group_by(& &1.model_path)
  |> Task.async_stream(
    fn {path, model_cases} ->
      case Boxic.DMN.TCK.ModelLoader.load(path) do
        {:ok, model} ->
          Enum.flat_map(model_cases, fn test_case ->
            ordinary = evaluate.(model, test_case, false)
            traced = evaluate.(model, test_case, true)

            if ordinary === traced,
              do: [],
              else: [{test_case.group, test_case.id, test_case.decision_name, ordinary, traced}]
          end)

        {:error, error} ->
          [{path, :load_error, error}]
      end
    end,
    ordered: true,
    timeout: :infinity,
    max_concurrency: System.schedulers_online()
  )
  |> Enum.flat_map(fn {:ok, failures} -> failures end)

revision = File.read!(Path.expand("../vendor/dmn-tck/PINNED_COMMIT", __DIR__)) |> String.trim()
IO.puts("DMN TCK revision: #{revision}")

IO.puts(
  "Exact traced/untraced equivalence: #{length(cases) - length(failures)}/#{length(cases)} result assertions"
)

if failures != [] do
  Enum.each(failures, fn failure -> IO.puts(inspect(failure, limit: :infinity)) end)
  System.halt(1)
end
