defmodule Boxic.DMN.ContainmentTest do
  use ExUnit.Case, async: false
  alias Boxic.DMN

  defp model(source) do
    {:ok, model} =
      DMN.load_xml("""
      <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/" id="m" name="M" namespace="urn:m">
        <decision id="d" name="D"><literalExpression><text>#{source}</text></literalExpression></decision>
      </definitions>
      """)

    model
  end

  test "event budgets are explicit and leave actual results/errors and execution unchanged" do
    model = model("for x in 1..20 return x + 1")
    {:ok, expected} = DMN.evaluate(model, "D")

    for budget <- [0, 100, 500] do
      assert {:ok, ^expected, trace} =
               DMN.evaluate_with_trace(model, "D", %{}, trace_max_bytes: budget)

      assert trace.truncated
      assert trace.truncation_reason == :event_size_limit

      assert :erlang.external_size(Map.new(trace.events, &{&1.event_id, &1})) <=
               max(budget, :erlang.external_size(%{}))
    end

    assert {:ok, ^expected, trace} =
             DMN.evaluate_with_trace(model, "D", %{}, trace_max_bytes: 100_000)

    refute trace.truncated

    assert {:error, %Boxic.FEEL.Error{code: :invalid_option}, _} =
             DMN.evaluate_with_trace(model, "D", %{}, trace_max_bytes: -1)

    broken = model(~s|1 * "text"|)
    assert {:error, error} = DMN.evaluate(broken, "D")
    assert {:error, ^error, trace} = DMN.evaluate_with_trace(broken, "D", %{}, trace_max_bytes: 0)
    assert trace.truncated
  end

  test "bounded DMN uses the profile gate and the same traced or ordinary execution" do
    model = model("sqrt(2)")
    assert {:ok, expected} = DMN.evaluate_bounded(model, "D")
    assert expected == DMN.evaluate(model, "D", %{}, profile: :bounded_v1)
    assert {:ok, {:ok, value, trace}} = DMN.evaluate_bounded(model, "D", %{}, trace: true)
    assert {:ok, value} == expected
    refute trace.truncated
    assert {:ok, {:error, diagnostics}} = DMN.evaluate_bounded(model("exp(1)"), "D")
    assert Enum.any?(diagnostics, &(&1.code == :unsupported_profile))
  end

  test "bounded services and truncated table captures retain ordinary outcomes" do
    {:ok, service} = DMN.load_file(Path.join(__DIR__, "fixtures/interchange/boxed_service.dmn"))

    assert {:ok, expected} =
             DMN.evaluate_service_bounded(service, "Boxed Service", [], trace: true)

    assert expected ==
             DMN.evaluate_service_with_trace(service, "Boxed Service", [],
               profile: :bounded_v1,
               trace_max_bytes: 1_000_000
             )

    {:ok, table} = DMN.load_file(Path.join(__DIR__, "fixtures/interchange/decision_table.dmn"))

    for age <- [17, 18], budget <- [0, 100, 500] do
      inputs = %{"Age" => Decimal.new(age)}
      {:ok, expected} = DMN.evaluate(table, "Classification", inputs)

      assert {:ok, ^expected, trace} =
               DMN.evaluate_with_trace(table, "Classification", inputs, trace_max_bytes: budget)

      assert trace.truncated
    end

    assert {:error, :invalid_execution_limits} =
             DMN.evaluate_bounded(table, "Classification", %{}, trace_max_bytes: :infinity)
  end

  test "real native XML timeout removes its temporary file and owned Port" do
    before_files = schema_files()
    before_ports = MapSet.new(Port.list())

    xml =
      "<definitions xmlns=\"https://www.omg.org/spec/DMN/20230324/MODEL/\" id=\"d\" name=\"D\" namespace=\"urn:d\"/>"

    assert {:error, [%{code: :schema_validation_timeout}]} =
             DMN.validate_xml_schema(xml, timeout: 0)

    assert schema_files() == before_files
    assert MapSet.subset?(MapSet.new(Port.list()), before_ports)
    assert :ok = DMN.validate_xml_schema(xml)
  end

  test "caller cancellation terminates the real native validator and removes its file" do
    xml =
      "<definitions xmlns=\"https://www.omg.org/spec/DMN/20230324/MODEL/\" id=\"d\" name=\"D\" namespace=\"urn:d\">" <>
        Enum.map_join(1..15_000, fn i ->
          "<decision id=\"d#{i}\" name=\"D#{i}\"><literalExpression><text>1</text></literalExpression></decision>"
        end) <> "</definitions>"

    before_files = schema_files()
    before_ports = MapSet.new(Port.list())
    caller = spawn(fn -> DMN.validate_xml_schema(xml) end)

    owner =
      await(fn ->
        case Process.info(caller, :monitors) do
          {:monitors, [{:process, pid}]} ->
            case Process.info(pid, :current_stacktrace) do
              {:current_stacktrace, stack} ->
                if Enum.any?(stack, fn {module, _function, _arity, _location} ->
                     module == Boxic.DMN.XML.SchemaValidator
                   end) do
                  # Pause only our actual resource owner, never a file server
                  # temporarily monitored during executable/file lookup.
                  :erlang.suspend_process(pid)
                  pid
                end

              _ ->
                nil
            end

          _ ->
            nil
        end
      end)

    monitor = Process.monitor(owner)
    caller_monitor = Process.monitor(caller)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :killed}, 1000
    :erlang.resume_process(owner)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 2000
    assert schema_files() == before_files
    assert MapSet.subset?(MapSet.new(Port.list()), before_ports)
  end

  defp schema_files do
    Path.wildcard(Path.join(System.tmp_dir!(), "boxic-dmn-schema-#{:os.getpid()}-*.xml"))
  end

  defp await(callback, attempts \\ 1000)
  defp await(_callback, 0), do: flunk("native validator did not enter expected state")

  defp await(callback, attempts) do
    case callback.() do
      nil ->
        Process.sleep(1)
        await(callback, attempts - 1)

      value ->
        value
    end
  end
end
