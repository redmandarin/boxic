defmodule Boxic.FEEL.Execution do
  @moduledoc """
  Optional monitored-process boundary for a single FEEL/DMN evaluation.

  `run/2` returns `{:ok, evaluation_return}` or a boundary error. It does not
  retry, log, persist or re-evaluate. Exceptions retain kind, reason and stack
  in `{:error, {:evaluation_exception, kind, reason, stack}}`.

  Options: `:timeout` in milliseconds (default 1000), `:max_heap_words`
  (default 8_000_000, minimum 1024). Both must be positive integers. Heap accounting includes
  shared binaries and is checked at GC, not at every allocation. This is not
  an OS sandbox, node-wide memory/concurrency limit or descendant-process limit.
  Callers own input/result sizes, concurrency and any host-function effects.
  Timeout/caller death kills the worker and waits for its monitor notification.
  """

  @type boundary_error ::
          :evaluation_timeout
          | :invalid_execution_limits
          | {:evaluation_worker_exit, term()}
          | {:evaluation_exception, atom(), term(), list()}

  @spec run((-> term()), keyword()) :: {:ok, term()} | {:error, boundary_error()}
  def run(callback, opts \\ []) when is_function(callback, 0) and is_list(opts) do
    timeout = Keyword.get(opts, :timeout, 1000)
    heap = Keyword.get(opts, :max_heap_words, 8_000_000)

    if is_integer(timeout) and timeout > 0 and is_integer(heap) and heap >= 1024 and
         Keyword.keys(opts) -- [:timeout, :max_heap_words] == [] do
      caller = self()
      deadline = System.monotonic_time(:millisecond) + timeout
      {owner, monitor} = spawn_monitor(fn -> own_evaluation(caller, callback, deadline, heap) end)

      receive do
        {^owner, :evaluation_boundary, result} ->
          receive do
            {:DOWN, ^monitor, :process, ^owner, :normal} ->
              result

            {:DOWN, ^monitor, :process, ^owner, reason} ->
              {:error, {:evaluation_worker_exit, reason}}
          end

        {:DOWN, ^monitor, :process, ^owner, reason} ->
          {:error, {:evaluation_worker_exit, reason}}
      end
    else
      {:error, :invalid_execution_limits}
    end
  end

  defp own_evaluation(caller, callback, deadline, heap) do
    Process.flag(:trap_exit, true)
    caller_monitor = Process.monitor(caller)
    owner = self()

    {worker, monitor} =
      :erlang.spawn_opt(fn -> evaluate(owner, callback) end, [
        :monitor,
        :link,
        {:max_heap_size,
         %{size: heap, kill: true, error_logger: false, include_shared_binaries: true}}
      ])

    result =
      receive do
        {^worker, :evaluation_return, result, finished_at} ->
          receive do
            {:DOWN, ^monitor, :process, ^worker, :normal} ->
              if finished_at <= deadline, do: result, else: {:error, :evaluation_timeout}

            {:DOWN, ^monitor, :process, ^worker, reason} ->
              {:error, {:evaluation_worker_exit, reason}}
          end

        {:DOWN, ^monitor, :process, ^worker, reason} ->
          {:error, {:evaluation_worker_exit, reason}}

        {:DOWN, ^caller_monitor, :process, ^caller, _reason} ->
          stop(worker, monitor)
          {:error, :caller_down}
      after
        max(0, deadline - System.monotonic_time(:millisecond)) ->
          stop(worker, monitor)
          {:error, :evaluation_timeout}
      end

    send(caller, {self(), :evaluation_boundary, result})
  end

  defp evaluate(owner, callback) do
    result =
      try do
        {:ok, callback.()}
      catch
        kind, reason -> {:error, {:evaluation_exception, kind, reason, __STACKTRACE__}}
      end

    send(owner, {self(), :evaluation_return, result, System.monotonic_time(:millisecond)})
  end

  defp stop(worker, monitor) do
    Process.exit(worker, :kill)

    receive do
      {:DOWN, ^monitor, :process, ^worker, _reason} -> :ok
    end
  end
end
