defmodule Boxic.FEEL.Profile do
  @moduledoc """
  Static, conservative capability gate for the `:wedge_v1` FEEL profile.
  This is a library profile policy, not a new FEEL semantics or certification.
  All branches and function references are checked without executing expressions.
  """
  alias Boxic.FEEL.{AST, Builtins, Error, Parser, Tokenizer}

  @excluded ~w(exp log sort list_replace)

  @spec validate(String.t(), :expression | :unary_tests) :: :ok | {:error, Error.t()}
  def validate(source, grammar \\ :expression)

  def validate(source, :expression) do
    with {:ok, ast} <- Boxic.FEEL.parse(source), do: validate_ast(ast)
  end

  def validate(source, :unary_tests) do
    with {:ok, tokens} <- Tokenizer.tokenize(String.trim(source)) do
      case Parser.validate_unary_tests(tokens, &validate_ast/1) do
        :ok -> :ok
        {:error, _} = error -> error
        _ -> {:error, Error.new(:invalid_syntax, "invalid unary tests")}
      end
    end
  end

  @doc false
  def validate_data(%Boxic.FEEL.Function{}),
    do: unsupported("callable inputs are outside wedge_v1")

  def validate_data(value) when is_function(value),
    do: unsupported("callable inputs are outside wedge_v1")

  def validate_data({kind, _}) when kind in [:builtin, :external_function],
    do: unsupported("callable inputs are outside wedge_v1")

  def validate_data(values) when is_map(values), do: values |> Map.values() |> validate_data()

  def validate_data(values) when is_list(values) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case validate_data(value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def validate_data(value) when is_tuple(value), do: value |> Tuple.to_list() |> validate_data()
  def validate_data(_value), do: :ok

  defp validate_ast(ast) do
    with :ok <- AST.validate(ast), do: supported(ast)
  end

  defp supported({:identifier, name}) when name in @excluded,
    do: unsupported("#{name} is excluded from wedge_v1, including function references")

  defp supported({:function, _parameters, _body}),
    do: unsupported("FEEL function definitions are outside wedge_v1")

  defp supported({:call, {:identifier, name}, arguments}) do
    case Builtins.resolve(name) do
      {:ok, {:builtin, _}} -> supported([{:identifier, name} | arguments])
      _ -> unsupported("only direct supported built-in calls are allowed in wedge_v1")
    end
  end

  defp supported({:call, _function, _arguments}),
    do: unsupported("dynamic function calls are outside wedge_v1")

  defp supported({:binary, :pow, base, exponent}) do
    case integer_exponent(exponent) do
      {:ok, integer} when abs(integer) <= 1024 ->
        supported(base)

      _ ->
        unsupported(
          "wedge_v1 powers require a literal integer exponent of magnitude at most 1024"
        )
    end
  end

  defp supported(ast) when is_tuple(ast), do: ast |> Tuple.to_list() |> supported()

  defp supported(nodes) when is_list(nodes) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case supported(node) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp supported(_value), do: :ok

  defp integer_exponent({:unary, :negate, ast}) do
    with {:ok, integer} <- integer_exponent(ast), do: {:ok, -integer}
  end

  defp integer_exponent({:literal, %Decimal{} = value}) do
    if Decimal.equal?(value, Decimal.round(value, 0, :down)),
      do: {:ok, Decimal.to_integer(value)},
      else: :error
  end

  defp integer_exponent(_ast), do: :error
  defp unsupported(message), do: {:error, Error.new(:unsupported_profile, message)}
end
