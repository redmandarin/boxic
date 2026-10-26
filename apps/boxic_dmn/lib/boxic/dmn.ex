defmodule Boxic.DMN do
  @moduledoc """
  Loads, validates, and evaluates DMN models.

  Use `load_file/1` when the input is a path and `load_xml/1` when the input is
  XML. `load/1` remains available for backwards compatibility and dispatches
  XML-looking input to `load_xml/1`; all other input is treated as a path.

  Decision, service and traced evaluation share FEEL's scoped 34-digit,
  half-even Decimal arithmetic policy, including decision-table aggregation.
  The caller's entire Decimal context is restored after success or failure.
  Numeric construction and exponent conformance are separate from that policy.
  """

  alias Boxic.DMN.Model
  alias Boxic.DMN.{Evaluator, Validator}
  alias Boxic.DMN.XML.Loader
  alias Boxic.DMN.XML.SchemaValidator
  alias Boxic.DMN.XML.Writer

  @typedoc "An error returned while reading or decoding a DMN document."
  @type load_error ::
          {:file_error, Path.t(), File.posix()}
          | :invalid_xml
          | :trailing_xml_content
          | :invalid_definitions_document

  @typedoc "A structural problem found while validating a normalized model."
  @type validation_error ::
          {atom(), term()}
          | {atom(), term(), term()}
          | {atom(), term(), term(), term()}

  @typedoc "An error produced while resolving or evaluating a decision."
  @type evaluation_error ::
          Boxic.FEEL.Error.t()
          | {atom(), term()}
          | {atom(), term(), term()}
          | {atom(), term(), term(), term()}

  @doc """
  Loads a DMN document from either an XML string or a file path.

  New code should prefer `load_xml/1` or `load_file/1`, which avoid input
  ambiguity.

      Boxic.DMN.load("<definitions id=\"example\" namespace=\"urn:example\"/>")
  """
  @spec load(String.t()) :: {:ok, Model.t()} | {:error, load_error()}
  @deprecated "use load_xml/1, load_xml/2, or load_file/1"
  defdelegate load(path_or_xml), to: Loader

  @doc """
  Loads a DMN document and its sibling imports from `path`.

      Boxic.DMN.load_file("priv/decisions/pricing.dmn")
  """
  @spec load_file(Path.t()) :: {:ok, Model.t()} | {:error, load_error()}
  defdelegate load_file(path), to: Loader

  @doc """
  Loads a DMN document from an XML string.

      Boxic.DMN.load_xml("<definitions id=\"example\" namespace=\"urn:example\"/>")
  """
  @spec load_xml(String.t()) ::
          {:ok, Model.t()} | {:error, load_error() | [Boxic.DMN.Diagnostic.t()]}
  defdelegate load_xml(xml), to: Loader

  @doc "Loads DMN XML using only an explicitly supplied import map or resolver."
  @spec load_xml(String.t(), keyword()) ::
          {:ok, Model.t()} | {:error, load_error() | [Boxic.DMN.Diagnostic.t()]}
  defdelegate load_xml(xml, opts), to: Loader

  @doc """
  Inspects a well-formed DMN document without claiming schema validity,
  executability, or writability.
  """
  @spec inspect_xml(String.t()) ::
          {:ok, Model.t()} | {:error, load_error() | [Boxic.DMN.Diagnostic.t()]}
  defdelegate inspect_xml(xml), to: Loader

  @doc "Validates XML against the packaged normative DMN 1.5 schema family."
  @spec validate_xml_schema(String.t()) :: :ok | {:error, [Boxic.DMN.Diagnostic.t()]}
  defdelegate validate_xml_schema(xml), to: SchemaValidator, as: :validate

  @doc """
  Validates a normalized DMN model.

      with {:ok, model} <- Boxic.DMN.load_xml(xml) do
        Boxic.DMN.validate(model)
      end
  """
  @spec validate(Model.t()) :: :ok | {:error, [validation_error()]}
  defdelegate validate(model), to: Validator

  @doc """
  Validates an existing model for one public capability.

  Supported capabilities are `:evaluation`, `:serialization`, and `:authoring`.
  This form returns stable `Boxic.DMN.Diagnostic` values.

  Evaluation and authoring validation parse every supported FEEL expression
  and unary test, including unused decisions, skipped branches, unmatched rule
  outputs, defaults and allowed values. No expression is evaluated and no input
  values are needed. Invalid supported syntax returns `:invalid_feel_syntax`
  diagnostics with element/position paths and the underlying FEEL error.

      with {:ok, model} <- Boxic.DMN.load_xml(xml),
           :ok <- Boxic.DMN.validate(model, for: :evaluation) do
        Boxic.DMN.evaluate(model, "Price", inputs)
      end

  Syntax success does not establish name resolution, type correctness, allowed
  input membership, termination or runtime success. Unsupported DMN constructs
  and expression languages retain their separate diagnostics. `validate/1`
  remains structural; serialization validation remains a fidelity check.
  Ordinary evaluation keeps its existing preflight and lazy expression behavior.
  """
  @spec validate(Model.t(), keyword()) :: :ok | {:error, [Boxic.DMN.Diagnostic.t()]}
  defdelegate validate(model, opts), to: Validator

  @doc """
  Encodes a normalized DMN model as deterministic DMN XML.

  The model must originate from the pinned DMN profile and have complete
  serialization fidelity. Supported options are:

    * `:format` — `:pretty` (default) or `:compact`;
    * `:xml_declaration` — whether to emit the UTF-8 XML declaration, defaulting
      to `true`.

  Pretty output uses two-space indentation, LF line endings, and one final
  newline. Compact output contains no presentation whitespace. FEEL text is
  escaped but otherwise preserved.
  """
  @spec encode_xml(Model.t(), keyword()) ::
          {:ok, String.t()} | {:error, [Boxic.DMN.SerializationError.t()]}
  def encode_xml(model, opts \\ []), do: Writer.encode(model, opts)

  @doc """
  Checks whether a normalized model can be encoded without data loss.

  This runs the same model, option, version, fidelity, identifier, reference,
  and unsupported-expression checks as `encode_xml/2` without producing XML.
  """
  @spec validate_serializable(Model.t(), keyword()) ::
          :ok | {:error, [Boxic.DMN.SerializationError.t()]}
  def validate_serializable(model, opts \\ []), do: Writer.validate_serializable(model, opts)

  @doc """
  Changes one existing supported expression or table-cell text in original XML.

  Select an expression by `%{element_id: id, text: text}`, or a cell by
  `%{table_id: id, rule_id: id, input_id: id, text: text}` (or `output_id`).
  A direct decision literal can use `%{decision_id: id, text: text}` when its
  literal expression has no ID.
  IDs must exist and be unambiguous. Only an optional `imports: map` is accepted.

  The revised document is strictly loaded and syntax-validated without evaluation.
  Unrelated loader-admitted XML content is retained, including descriptions,
  annotations, diagrams and opaque extensions. This does not grant extensions
  executable meaning. Unknown XML names, processing instructions and non-UTF-8
  documents are refused. Preservation is semantic, not byte-for-byte; existing
  normalized-model writer fidelity refusals are unchanged.
  """
  @spec edit_xml(String.t(), Boxic.DMN.XML.Editor.edit(), keyword()) ::
          {:ok, String.t()} | {:error, [Boxic.DMN.Diagnostic.t()] | load_error()}
  def edit_xml(xml, edit, opts \\ []), do: Boxic.DMN.XML.Editor.edit(xml, edit, opts)

  @doc """
  Evaluates a named decision using the supplied input context.

      Boxic.DMN.evaluate(model, "Price", %{"quantity" => Decimal.new("2")})
  """
  @spec evaluate(Model.t(), String.t(), map()) ::
          {:ok, term()} | {:error, evaluation_error()}
  def evaluate(model, decision_name, context \\ %{}),
    do: Evaluator.evaluate(model, decision_name, context)

  @doc """
  Evaluates a named decision with evaluator options.

      Boxic.DMN.evaluate(model, "Price", inputs,
        external_functions: MyApp.DecisionFunctions
      )
  """
  @spec evaluate(Model.t(), String.t(), map(), keyword()) ::
          {:ok, term()} | {:error, evaluation_error()}
  defdelegate evaluate(model, decision_name, context, opts), to: Evaluator

  @doc """
  Evaluates a decision once and returns its result with execution evidence.

  Returns `{:ok, value, trace}` or `{:error, original_reason, trace}`. Existing
  evaluator options apply. The trace includes partial evidence on tagged errors;
  exceptions/exits still propagate. Native values are retained without truncation,
  logging or persistence. See `Boxic.DMN.Trace` and the tracing design document
  for coverage, contribution semantics and memory behavior.

      Boxic.DMN.evaluate_with_trace(model, "Price", inputs)
  """
  @spec evaluate_with_trace(Model.t(), String.t(), map(), keyword()) ::
          {:ok, term(), Boxic.DMN.Trace.t()}
          | {:error, evaluation_error() | atom() | [Boxic.DMN.Diagnostic.t()],
             Boxic.DMN.Trace.t()}
  def evaluate_with_trace(model, decision_name, context \\ %{}, opts \\ []),
    do: Evaluator.evaluate_with_trace(model, decision_name, context, opts)

  @doc """
  Evaluates a named decision service.

      Boxic.DMN.evaluate_service(model, "Pricing Service", %{"order" => order})
  """
  @spec evaluate_service(Model.t(), String.t(), map() | list()) ::
          {:ok, term()} | {:error, evaluation_error()}
  defdelegate evaluate_service(model, service_name, arguments), to: Evaluator

  @doc "Evaluates a decision service with the same trusted host-function options as `evaluate/4`."
  @spec evaluate_service(Model.t(), String.t(), map() | list(), keyword()) ::
          {:ok, term()} | {:error, evaluation_error()}
  defdelegate evaluate_service(model, service_name, arguments, opts), to: Evaluator

  @doc "Evaluates a decision service once with the same trace contract as `evaluate_with_trace/4`."
  @spec evaluate_service_with_trace(Model.t(), String.t(), map() | list(), keyword()) ::
          {:ok, term(), Boxic.DMN.Trace.t()}
          | {:error, evaluation_error() | atom() | [Boxic.DMN.Diagnostic.t()],
             Boxic.DMN.Trace.t()}
  def evaluate_service_with_trace(model, service_name, arguments, opts \\ []),
    do: Evaluator.evaluate_service_with_trace(model, service_name, arguments, opts)
end
