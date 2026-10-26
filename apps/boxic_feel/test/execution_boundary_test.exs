defmodule Boxic.FEEL.ExecutionBoundaryTest do
  use ExUnit.Case, async: true
  alias Boxic.FEEL
  alias Boxic.FEEL.Execution

  test "bounded public evaluation preserves the nested ordinary return and caller context" do
    before = Decimal.Context.get()
    assert {:ok, ordinary} = FEEL.evaluate_bounded("1 / 3")
    assert ordinary == FEEL.evaluate("1 / 3")
    assert Decimal.Context.get() === before

    assert {:ok, {:error, %FEEL.Error{code: :unsupported_profile}}} =
             FEEL.evaluate_bounded("exp(1)")

    assert {:error, :invalid_execution_limits} = FEEL.evaluate_bounded("1", %{}, timeout: 0)

    assert {:error, {:evaluation_exception, :error, %ArgumentError{}, _stack}} =
             Execution.run(fn -> raise ArgumentError, "unrelated bug" end)
  end

  test "real FEEL expansion hits deadline or GC heap bound without late mailbox results" do
    source = "for x in 1..10000000 return x"

    assert {:error, :evaluation_timeout} =
             FEEL.evaluate_bounded(source, %{}, timeout: 1, max_heap_words: 100_000_000)

    assert {:error, {:evaluation_worker_exit, :killed}} =
             FEEL.evaluate_bounded(source, %{}, timeout: 5000, max_heap_words: 2048)

    refute_receive {:DOWN, _, :process, _, _}, 20
    assert {:ok, {:ok, value}} = FEEL.evaluate_bounded("2 + 2")
    assert Decimal.equal?(value, 4)
  end

  test "caller death reaps the actual evaluating worker" do
    parent = self()

    registry =
      FEEL.ExternalFunctions.new([
        {"wait",
         fn ->
           send(parent, {:worker, self()})

           receive do
             :monitored -> Process.sleep(:infinity)
           end
         end, returns: :feel}
      ])

    caller =
      spawn(fn ->
        Execution.run(fn -> FEEL.evaluate("wait()", %{}, external_functions: registry) end,
          timeout: 5000
        )
      end)

    assert_receive {:worker, worker}, 1000
    monitor = Process.monitor(worker)
    send(worker, :monitored)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 1000
  end
end
