defmodule Boxic.FEEL.Profile do
  @moduledoc """
  Static, conservative capability gate for the `:bounded_v1` FEEL profile.
  This is a library profile policy, not a new FEEL semantics or certification.
  All branches and function references are checked without executing expressions.
  Dynamic power operands are admitted statically, with integer/domain/resource
  checks at actual execution. The context marker is invocation-local.
  """
  alias Boxic.FEEL.{AST, Builtins, Error, Parser, Tokenizer}

  @excluded ~w(exp log sort list_replace)
  @exponent_domain 999_999_999
  @exponent_limit 1024

  @doc false
  def attach(context, opts) do
    case Keyword.get(opts, :profile) do
      nil ->
        {:ok, context}

      :bounded_v1 ->
        if Keyword.has_key?(opts, :external_functions),
          do: unsupported("external functions are outside bounded_v1"),
          else: {:ok, Map.put(context, __MODULE__, :bounded_v1)}

      _ ->
        {:error, Error.new(:invalid_option, "unknown evaluation profile")}
    end
  end

  @doc false
  def power_exponent(nil), do: {:ok, nil}

  def power_exponent(%Decimal{} = value) do
    cond do
      not Decimal.integer?(value) ->
        unsupported("fractional exponents are outside bounded_v1")

      outside?(value, @exponent_domain) ->
        {:ok, nil}

      outside?(value, @exponent_limit) ->
        {:error,
         Error.new(
           :execution_limit_exceeded,
           "bounded_v1 integer exponent magnitude exceeds #{@exponent_limit}"
         )}

      true ->
        {:ok, Decimal.to_integer(value)}
    end
  end

  def power_exponent(_value),
    do: {:error, Error.new(:type_error, "exponentiation requires numbers")}

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
    do: unsupported("callable inputs are outside bounded_v1")

  def validate_data(value) when is_function(value),
    do: unsupported("callable inputs are outside bounded_v1")

  def validate_data({kind, _}) when kind in [:builtin, :external_function],
    do: unsupported("callable inputs are outside bounded_v1")

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

  @doc false
  def validate_ast(ast) do
    with :ok <- AST.validate(ast), do: supported(ast)
  end

  defp supported({:identifier, name}) when name in @excluded,
    do: unsupported("#{name} is excluded from bounded_v1, including function references")

  defp supported({:function, _parameters, _body}),
    do: unsupported("FEEL function definitions are outside bounded_v1")

  defp supported({:call, {:identifier, name}, arguments}) do
    case Builtins.resolve(name) do
      {:ok, {:builtin, _}} -> supported([{:identifier, name} | arguments])
      _ -> unsupported("only direct supported built-in calls are allowed in bounded_v1")
    end
  end

  defp supported({:call, _function, _arguments}),
    do: unsupported("dynamic function calls are outside bounded_v1")

  defp supported({:binary, :pow, base, exponent}) do
    with :ok <- supported(base),
         :ok <- supported(exponent),
         do: literal_exponent(exponent)
  end

  defp supported({:literal, value}) do
    with {:ok, value} <- Boxic.FEEL.Number.admit(value), do: validate_data(value)
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

  defp literal_exponent({:unary, :negate, ast}), do: literal_exponent(ast)

  defp literal_exponent({:literal, %Decimal{} = value}) do
    with {:ok, value} <- Boxic.FEEL.Number.admit(value) do
      case power_exponent(value) do
        {:ok, _value} -> :ok
        {:error, %Error{message: message}} -> unsupported(message)
      end
    end
  end

  defp literal_exponent(_ast), do: :ok

  defp outside?(value, magnitude),
    do: Decimal.compare(value, -magnitude) == :lt or Decimal.compare(value, magnitude) == :gt

  defp unsupported(message), do: {:error, Error.new(:unsupported_profile, message)}
end
