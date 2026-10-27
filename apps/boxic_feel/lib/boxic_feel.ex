defmodule Boxic.FEEL do
  @moduledoc """
  Parses and evaluates FEEL expressions.

  The public facade accepts FEEL source through `parse/1` and `evaluate/2`, or
  an already parsed syntax tree through `evaluate_ast/2`.

  Source, AST and unary-test evaluation use a scoped Decimal context with
  precision 34 and half-even rounding. The caller's full context is restored
  after success or failure; nested public calls use the same arithmetic policy.
  Explicit rounding functions retain their own modes. Undefined numeric results
  become local FEEL nulls at arithmetic operations, not a fallback for an entire
  evaluation. Other errors retain their existing behavior.

  Numeric admission uses the same bounded nearest-even mapping for literals,
  Decimal inputs and results. Malformed/nonfinite/out-of-domain admission returns
  `:invalid_number`; undefined arithmetic returns FEEL null. Parsing includes
  numeric admission and does not establish complete model/runtime validity.
  """

  alias Boxic.FEEL.{
    Arithmetic,
    AST,
    Error,
    Evaluator,
    ExternalFunctions,
    Parser,
    Profile,
    Tokenizer
  }

  @type ast ::
          {:literal, term()}
          | {:identifier, String.t()}
          | {:unary, atom(), ast()}
          | {:binary, atom(), ast(), ast()}
          | {:list, [ast()]}
          | {:context, [{String.t(), ast()}]}
          | {:path, ast(), String.t()}
          | {:filter, ast(), ast()}
          | {:range, boolean(), boolean(), ast(), ast()}
          | {:in, ast(), ast()}
          | {:unary_test, atom(), ast()}
          | {:unary_tests, [ast()]}
          | {:sequence, ast(), ast()}
          | {:if, ast(), ast(), ast()}
          | {:for, String.t(), ast(), ast()}
          | {:for, [{String.t(), ast()}], ast()}
          | {:quantifier, :some | :every, String.t(), ast(), ast()}
          | {:between, ast(), ast(), ast()}
          | {:instance_of, ast(), String.t()}
          | {:function, [String.t()], ast()}
          | {:call, ast(), [ast()]}
  @type context :: %{optional(String.t()) => term()}

  @doc "Evaluates once in an opt-in deadline/heap boundary; returns a nested evaluation result."
  @spec evaluate_bounded(String.t(), context(), keyword()) :: {:ok, term()} | {:error, term()}
  def evaluate_bounded(expression, context \\ %{}, limits \\ []) do
    Boxic.FEEL.Execution.run(
      fn ->
        evaluate(expression, context, profile: :bounded_v1)
      end,
      limits
    )
  end

  @doc """
  Parses a FEEL expression into Boxic's public AST representation.

      iex> Boxic.FEEL.parse("1 + 2")
      {:ok, {:binary, :plus, {:literal, Decimal.new("1")}, {:literal, Decimal.new("2")}}}
  """
  @spec parse(String.t()) :: {:ok, ast()} | {:error, Error.t()}
  def parse(expression) when is_binary(expression) do
    trimmed = String.trim(expression)

    if trimmed == "" do
      {:error, %Error{code: :empty_expression, message: "expression cannot be empty"}}
    else
      with {:ok, tokens} <- Tokenizer.tokenize(trimmed),
           {:ok, ast, []} <- Parser.parse_expression(tokens),
           :ok <- AST.validate(ast) do
        {:ok, ast}
      else
        {:ok, _ast, rest} ->
          {:error, %Error{code: :invalid_syntax, message: "unexpected tokens: #{inspect(rest)}"}}

        {:error, %Error{} = error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Checks FEEL unary-test syntax without evaluating tests or their operands.

  Accepts dash, positive tests, comma-separated alternatives and `not(...)`.
  Success does not establish name resolution, types or runtime success.

      iex> Boxic.FEEL.validate_unary_tests("< 18, >= 65")
      :ok
  """
  @spec validate_unary_tests(String.t()) :: :ok | {:error, Error.t()}
  def validate_unary_tests(expression) when is_binary(expression) do
    with {:ok, tokens} <- Tokenizer.tokenize(String.trim(expression)) do
      case Parser.validate_unary_tests(tokens) do
        :ok -> :ok
        {:error, %Error{} = error} -> {:error, error}
        {:ok, rest} -> {:error, Error.new(:invalid_syntax, "unexpected tokens: #{inspect(rest)}")}
      end
    end
  end

  @doc """
  Parses and evaluates a FEEL expression.

      iex> Boxic.FEEL.evaluate("price * quantity", %{
      ...>   "price" => Decimal.new("12.50"),
      ...>   "quantity" => Decimal.new("2")
      ...> })
      {:ok, Decimal.new("25.00")}
  """
  @spec evaluate(String.t(), context()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate(expression, context \\ %{}) when is_binary(expression) and is_map(context) do
    Arithmetic.with_context(fn ->
      with {:ok, ast} <- parse(expression), do: evaluate_ast(ast, context)
    end)
  end

  @doc "Evaluates FEEL with a trusted external-function environment or the opt-in bounded_v1 profile."
  @spec evaluate(String.t(), context(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate(expression, context, opts)
      when is_binary(expression) and is_map(context) and is_list(opts) do
    Arithmetic.with_context(fn ->
      with {:ok, context} <- evaluator_context(context, opts),
           {:ok, ast} <- parse(expression) do
        evaluate_ast(ast, context)
      end
    end)
  end

  @doc "Evaluates an AST previously returned by `parse/1`."
  @spec evaluate_ast(ast(), context()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate_ast(ast, context) when is_map(context) do
    Arithmetic.with_context(fn ->
      with :ok <- validate_evaluation_ast(ast, context),
           {:ok, context} <- Boxic.FEEL.Number.admit(context),
           {:ok, value} <- Evaluator.eval(ast, context),
           do: Boxic.FEEL.Number.admit(value)
    end)
  end

  @doc "Evaluates a parsed AST with external-function options or profile: :bounded_v1."
  @spec evaluate_ast(ast(), context(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate_ast(ast, context, opts) when is_map(context) and is_list(opts) do
    Arithmetic.with_context(fn ->
      with {:ok, context} <- evaluator_context(context, opts), do: evaluate_ast(ast, context)
    end)
  end

  @doc """
  Evaluates a FEEL unary test against `value`.

      iex> Boxic.FEEL.evaluate_unary_test(">= 18", Decimal.new("21"))
      {:ok, true}
  """
  @spec evaluate_unary_test(String.t(), term(), context()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def evaluate_unary_test(test_expression, value, context \\ %{})
      when is_binary(test_expression) and is_map(context) do
    Arithmetic.with_context(fn ->
      with :ok <- validate_unary_evaluation(test_expression, context),
           {:ok, value} <- Boxic.FEEL.Number.admit(value),
           {:ok, context} <- Boxic.FEEL.Number.admit(context),
           do: Evaluator.evaluate_unary_test(test_expression, value, context)
    end)
  end

  @doc "Evaluates a unary test with external-function options or profile: :bounded_v1."
  @spec evaluate_unary_test(String.t(), term(), context(), keyword()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def evaluate_unary_test(test_expression, value, context, opts)
      when is_binary(test_expression) and is_map(context) and is_list(opts) do
    Arithmetic.with_context(fn ->
      with {:ok, context} <- evaluator_context(context, opts) do
        evaluate_unary_test(test_expression, value, context)
      end
    end)
  end

  defp evaluator_context(context, opts) do
    with {:ok, context} <- Profile.attach(context, opts) do
      case Keyword.get(opts, :external_functions) do
        nil ->
          {:ok, context}

        registry ->
          precedence = Keyword.get(opts, :external_function_precedence, :builtins)

          if precedence in [:builtins, :registered] do
            {:ok, ExternalFunctions.attach(context, registry, precedence)}
          else
            {:error,
             Error.new(
               :invalid_option,
               "external_function_precedence must be :builtins or :registered"
             )}
          end
      end
    end
  end

  defp validate_evaluation_ast(ast, %{Profile => :bounded_v1} = context) do
    with :ok <- Profile.validate_data(context), do: Profile.validate_ast(ast)
  end

  defp validate_evaluation_ast(ast, _context), do: AST.validate(ast)

  defp validate_unary_evaluation(expression, %{Profile => :bounded_v1}),
    do: Profile.validate(expression, :unary_tests)

  defp validate_unary_evaluation(_expression, _context), do: :ok
end
