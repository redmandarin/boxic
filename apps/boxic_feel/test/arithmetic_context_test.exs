defmodule Boxic.FEEL.ArithmeticContextTest do
  use ExUnit.Case, async: true

  alias Boxic.FEEL
  alias Boxic.FEEL.ExternalFunctions

  @even "1234567890123456789012345678901234"
  @odd "1234567890123456789012345678901235"
  @next_even "1234567890123456789012345678901236"
  @third Decimal.new("0.3333333333333333333333333333333333")

  defmodule RaisingRegistry do
    def external_functions do
      Decimal.Context.set(%Decimal.Context{precision: 2, flags: [:inexact]})
      raise ArgumentError, "registry programming failure"
    end
  end

  defmodule ThrowingRegistry do
    def external_functions, do: throw(:registry_failure)
  end

  test "exact positive and negative halfway cases use 34 digits and ties to even" do
    cases = [
      {"#{@even} + 0.5", @even},
      {"#{@odd} + 0.5", @next_even},
      {"-#{@even} - 0.5", "-" <> @even},
      {"-#{@odd} - 0.5", "-" <> @next_even}
    ]

    for caller <- caller_contexts(), {source, expected} <- cases do
      Decimal.Context.with(caller, fn ->
        assert {:ok, Decimal.new(expected)} == FEEL.evaluate(source)
        assert Decimal.Context.get() === caller
      end)
    end
  end

  test "source, AST and unary-test entry points ignore caller precision, rounding and traps" do
    {:ok, ast} = FEEL.parse("value / 3")
    {:ok, function} = FEEL.evaluate("function(n) n / 3")
    context = %{"value" => Decimal.new(1)}
    opts = [external_functions: ExternalFunctions.new()]

    entries = [
      fn -> FEEL.evaluate("1 / 3") end,
      fn -> FEEL.evaluate("value / 3", context) end,
      fn -> FEEL.evaluate("value / 3", context, opts) end,
      fn -> FEEL.evaluate_ast(ast, context) end,
      fn -> FEEL.evaluate_ast(ast, context, opts) end,
      fn -> FEEL.evaluate("f(1)", %{"f" => function}) end
    ]

    for caller <- caller_contexts() do
      Decimal.Context.with(caller, fn ->
        for entry <- entries do
          assert {:ok, @third} == entry.()
          assert Decimal.Context.get() === caller
        end

        assert {:ok, true} = FEEL.evaluate_unary_test("= 1 / 3", @third)
        assert Decimal.Context.get() === caller
        assert {:ok, true} = FEEL.evaluate_unary_test("= value / 3", @third, context)
        assert Decimal.Context.get() === caller
        assert {:ok, true} = FEEL.evaluate_unary_test("= value / 3", @third, context, opts)
        assert Decimal.Context.get() === caller
      end)
    end
  end

  test "explicit rounding built-ins retain their own modes" do
    cases = [
      {"decimal(2.5, 0)", "2"},
      {"decimal(3.5, 0)", "4"},
      {"round half up(2.5, 0)", "3"},
      {"round half up(-2.5, 0)", "-3"},
      {"round half down(2.5, 0)", "2"},
      {"round half down(-2.5, 0)", "-2"},
      {"round up(-2.5, 0)", "-3"},
      {"round down(-2.5, 0)", "-2"},
      {"floor(-2.5)", "-3"},
      {"ceiling(-2.5)", "-2"},
      {"round(2.5)", "3"}
    ]

    for caller <- caller_contexts(), {source, expected} <- cases do
      Decimal.Context.with(caller, fn ->
        assert {:ok, Decimal.new(expected)} == FEEL.evaluate(source)
        assert Decimal.Context.get() === caller
      end)
    end
  end

  test "undefined numeric results remain local nulls, not whole-expression fallbacks" do
    context = %{"large" => Decimal.new(1, 9, 6_144)}

    for caller <- caller_contexts() do
      Decimal.Context.with(caller, fn ->
        assert {:ok, [nil, nil, nil, nil, nil, nil, Decimal.new(1)]} ==
                 FEEL.evaluate(
                   "[large * 10, large + large, sum([large, large]), product([large, 10]), (-1) ** 0.5, exp(10000), 1]",
                   context
                 )

        assert {:ok, [nil, nil, nil, Decimal.new(1)]} ==
                 FEEL.evaluate("[1 / 0, 0 / 0, sqrt(-1), 1]")

        assert {:error, %FEEL.Error{code: :invalid_number}} =
                 FEEL.evaluate("nan * 1", %{"nan" => Decimal.new("NaN")})

        assert Decimal.Context.get() === caller
        assert {:error, %FEEL.Error{code: :type_error}} = FEEL.evaluate(~s(1 * "text"))
        assert Decimal.Context.get() === caller
      end)
    end
  end

  test "syntax, AST and option errors restore the full caller context" do
    caller = hd(caller_contexts())

    Decimal.Context.with(caller, fn ->
      assert {:error, %FEEL.Error{code: :invalid_syntax}} = FEEL.evaluate("if )")
      assert Decimal.Context.get() === caller
      assert {:error, %FEEL.Error{code: :invalid_ast}} = FEEL.evaluate_ast(:invalid, %{})
      assert Decimal.Context.get() === caller

      assert {:error, %FEEL.Error{code: :invalid_option}} =
               FEEL.evaluate("1", %{},
                 external_functions: ExternalFunctions.new(),
                 external_function_precedence: :bad
               )

      assert Decimal.Context.get() === caller
    end)
  end

  test "unrelated registry exceptions and throws propagate without leaking context" do
    caller = hd(caller_contexts())

    Decimal.Context.with(caller, fn ->
      assert_raise ArgumentError, "registry programming failure", fn ->
        FEEL.evaluate("1", %{}, external_functions: RaisingRegistry)
      end

      assert Decimal.Context.get() === caller

      assert catch_throw(
               FEEL.evaluate_ast({:literal, Decimal.new(1)}, %{},
                 external_functions: ThrowingRegistry
               )
             ) == :registry_failure

      assert Decimal.Context.get() === caller
    end)
  end

  test "registered provider failures retain their existing tagged errors" do
    caller = hd(caller_contexts())

    for callback <- [
          fn -> raise "private" end,
          fn -> raise Decimal.Error, signal: :invalid_operation, reason: "provider failure" end
        ] do
      registry = ExternalFunctions.new([{"provider", callback, []}])

      Decimal.Context.with(caller, fn ->
        assert {:error, %FEEL.Error{code: :external_function_error}} =
                 FEEL.evaluate("provider()", %{}, external_functions: registry)

        assert Decimal.Context.get() === caller
      end)
    end
  end

  test "nested public evaluations restore the host's enclosing temporary context" do
    owner = self()

    temporary = %Decimal.Context{
      precision: 3,
      rounding: :up,
      flags: [:rounded],
      traps: [:inexact]
    }

    registry =
      ExternalFunctions.new([
        {"nested",
         fn ->
           before = Decimal.Context.get()
           send(owner, {:engine_context, before.precision, before.rounding, before.flags})

           value =
             Decimal.Context.with(temporary, fn ->
               {:ok, value} = FEEL.evaluate("1 / 3")
               send(owner, {:temporary_restored, Decimal.Context.get() === temporary})
               value
             end)

           send(owner, {:enclosing_restored, Decimal.Context.get() === before})
           value
         end, []}
      ])

    for caller <- caller_contexts() do
      Decimal.Context.with(caller, fn ->
        assert {:ok, @third} == FEEL.evaluate("nested()", %{}, external_functions: registry)
        assert Decimal.Context.get() === caller
        assert_receive {:engine_context, 34, :half_even, []}
        assert_receive {:temporary_restored, true}
        assert_receive {:enclosing_restored, true}
      end)
    end
  end

  defp caller_contexts do
    [
      %Decimal.Context{
        precision: 6,
        rounding: :down,
        emin: -9,
        emax: 9,
        flags: [:rounded, :underflow],
        traps: [:inexact, :rounded, :overflow]
      },
      %Decimal.Context{precision: 34, rounding: :half_up, flags: [:inexact], traps: []},
      %Decimal.Context{
        precision: 50,
        rounding: :ceiling,
        emin: :infinity,
        emax: :infinity,
        flags: [:underflow],
        traps: [:invalid_operation, :division_by_zero, :inexact]
      }
    ]
  end
end
