defmodule FSM.Effects.Telemetry do
  @moduledoc """
  Comprehensive telemetry and observability for the FSM Effects System.

  This module provides detailed instrumentation, metrics collection, and monitoring
  capabilities for effect execution, performance analysis, and debugging.

  ## Telemetry Events

  The Effects System emits the following telemetry events:

  - `[:fsm, :effect, :started]` - Effect execution begins
  - `[:fsm, :effect, :completed]` - Effect execution completes successfully
  - `[:fsm, :effect, :failed]` - Effect execution fails
  - `[:fsm, :effect, :cancelled]` - Effect execution is cancelled
  - `[:fsm, :effect, :timeout]` - Effect execution times out
  - `[:fsm, :effect, :retry]` - Effect retry attempt
  - `[:fsm, :effect, :circuit_breaker]` - Circuit breaker state changes
  - `[:fsm, :effect, :composition]` - Composition operator events

  ## Usage

      # Attach telemetry handlers
      FSM.Effects.Telemetry.attach_handlers()

      # Custom handler
      :telemetry.attach(
        "my-effect-handler",
        [:fsm, :effect, :completed],
        &MyModule.handle_effect_completed/4,
        nil
      )
  """

  require Logger

  @typedoc "Telemetry event name"
  @type event_name :: [atom()]

  @typedoc "Telemetry measurements"
  @type measurements :: %{
    optional(:duration_us) => non_neg_integer(),
    optional(:memory_bytes) => non_neg_integer(),
    optional(:count) => non_neg_integer(),
    optional(:rate) => float()
  }

  @typedoc "Telemetry metadata"
  @type metadata :: %{
    optional(:execution_id) => String.t(),
    optional(:effect_type) => atom(),
    optional(:fsm_id) => String.t(),
    optional(:tenant_id) => String.t(),
    optional(:state) => atom(),
    optional(:event) => atom(),
    optional(:error) => any(),
    optional(:attempt) => pos_integer(),
    optional(:max_attempts) => pos_integer(),
    optional(:backoff_ms) => non_neg_integer()
  }

  # Public API

  @doc """
  Attaches default telemetry handlers for effects monitoring.
  """
  @spec attach_handlers() :: :ok
  def attach_handlers do
    events = [
      [:fsm, :effect, :started],
      [:fsm, :effect, :completed],
      [:fsm, :effect, :failed],
      [:fsm, :effect, :cancelled],
      [:fsm, :effect, :timeout],
      [:fsm, :effect, :retry],
      [:fsm, :effect, :circuit_breaker],
      [:fsm, :effect, :composition]
    ]

    :telemetry.attach_many(
      "fsm-effects-telemetry",
      events,
      &handle_telemetry_event/4,
      %{}
    )

    Logger.info("FSM Effects telemetry handlers attached")
    :ok
  end

  @doc """
  Detaches all FSM Effects telemetry handlers.
  """
  @spec detach_handlers() :: :ok
  def detach_handlers do
    :telemetry.detach("fsm-effects-telemetry")
    Logger.info("FSM Effects telemetry handlers detached")
    :ok
  end

  @doc """
  Emits a telemetry event for effect execution start.
  """
  @spec emit_effect_started(String.t(), atom(), metadata()) :: :ok
  def emit_effect_started(execution_id, effect_type, metadata \\ %{}) do
    enhanced_metadata = Map.merge(metadata, %{
      execution_id: execution_id,
      effect_type: effect_type,
      timestamp: DateTime.utc_now()
    })

    :telemetry.execute(
      [:fsm, :effect, :started],
      %{count: 1},
      enhanced_metadata
    )
  end

  @doc """
  Emits a telemetry event for successful effect completion.
  """
  @spec emit_effect_completed(String.t(), atom(), non_neg_integer(), metadata()) :: :ok
  def emit_effect_completed(execution_id, effect_type, duration_us, metadata \\ %{}) do
    enhanced_metadata = Map.merge(metadata, %{
      execution_id: execution_id,
      effect_type: effect_type,
      timestamp: DateTime.utc_now()
    })

    :telemetry.execute(
      [:fsm, :effect, :completed],
      %{duration_us: duration_us, count: 1},
      enhanced_metadata
    )
  end

  @doc """
  Emits a telemetry event for effect execution failure.
  """
  @spec emit_effect_failed(String.t(), atom(), any(), metadata()) :: :ok
  def emit_effect_failed(execution_id, effect_type, error, metadata \\ %{}) do
    enhanced_metadata = Map.merge(metadata, %{
      execution_id: execution_id,
      effect_type: effect_type,
      error: error,
      timestamp: DateTime.utc_now()
    })

    :telemetry.execute(
      [:fsm, :effect, :failed],
      %{count: 1},
      enhanced_metadata
    )
  end

  @doc """
  Emits a telemetry event for effect cancellation.
  """
  @spec emit_effect_cancelled(String.t(), atom(), atom(), metadata()) :: :ok
  def emit_effect_cancelled(execution_id, effect_type, reason, metadata \\ %{}) do
    enhanced_metadata = Map.merge(metadata, %{
      execution_id: execution_id,
      effect_type: effect_type,
      cancellation_reason: reason,
      timestamp: DateTime.utc_now()
    })

    :telemetry.execute(
      [:fsm, :effect, :cancelled],
      %{count: 1},
      enhanced_metadata
    )
  end

  @doc """
  Emits a telemetry event for effect timeout.
  """
  @spec emit_effect_timeout(String.t(), atom(), non_neg_integer(), metadata()) :: :ok
  def emit_effect_timeout(execution_id, effect_type, timeout_ms, metadata \\ %{}) do
    enhanced_metadata = Map.merge(metadata, %{
      execution_id: execution_id,
      effect_type: effect_type,
      timeout_ms: timeout_ms,
      timestamp: DateTime.utc_now()
    })

    :telemetry.execute(
      [:fsm, :effect, :timeout],
      %{count: 1, timeout_ms: timeout_ms},
      enhanced_metadata
    )
  end

  @doc """
  Emits a telemetry event for effect retry attempt.
  """
  @spec emit_effect_retry(String.t(), atom(), pos_integer(), pos_integer(), metadata()) :: :ok
  def emit_effect_retry(execution_id, effect_type, attempt, max_attempts, metadata \\ %{}) do
    enhanced_metadata = Map.merge(metadata, %{
      execution_id: execution_id,
      effect_type: effect_type,
      attempt: attempt,
      max_attempts: max_attempts,
      timestamp: DateTime.utc_now()
    })

    :telemetry.execute(
      [:fsm, :effect, :retry],
      %{count: 1, attempt: attempt, max_attempts: max_attempts},
      enhanced_metadata
    )
  end

  @doc """
  Emits a telemetry event for circuit breaker state changes.
  """
  @spec emit_circuit_breaker_event(String.t(), atom(), atom(), metadata()) :: :ok
  def emit_circuit_breaker_event(breaker_id, old_state, new_state, metadata \\ %{}) do
    enhanced_metadata = Map.merge(metadata, %{
      breaker_id: breaker_id,
      old_state: old_state,
      new_state: new_state,
      timestamp: DateTime.utc_now()
    })

    :telemetry.execute(
      [:fsm, :effect, :circuit_breaker],
      %{count: 1},
      enhanced_metadata
    )
  end

  @doc """
  Emits a telemetry event for composition operator execution.
  """
  @spec emit_composition_event(atom(), [atom()], non_neg_integer(), metadata()) :: :ok
  def emit_composition_event(composition_type, effect_types, duration_us, metadata \\ %{}) do
    enhanced_metadata = Map.merge(metadata, %{
      composition_type: composition_type,
      effect_types: effect_types,
      effect_count: length(effect_types),
      timestamp: DateTime.utc_now()
    })

    :telemetry.execute(
      [:fsm, :effect, :composition],
      %{duration_us: duration_us, effect_count: length(effect_types)},
      enhanced_metadata
    )
  end

  @doc """
  Gets comprehensive metrics about effects execution.
  """
  @spec get_execution_metrics(keyword()) :: map()
  def get_execution_metrics(opts \\ []) do
    time_window = Keyword.get(opts, :time_window, 300_000) # 5 minutes
    tenant_id = Keyword.get(opts, :tenant_id)
    effect_type = Keyword.get(opts, :effect_type)

    # This would typically query a metrics store
    # For now, return example metrics
    %{
      total_executions: get_metric_value(:total_executions, time_window, tenant_id, effect_type),
      successful_executions: get_metric_value(:successful_executions, time_window, tenant_id, effect_type),
      failed_executions: get_metric_value(:failed_executions, time_window, tenant_id, effect_type),
      cancelled_executions: get_metric_value(:cancelled_executions, time_window, tenant_id, effect_type),
      timeout_executions: get_metric_value(:timeout_executions, time_window, tenant_id, effect_type),
      average_duration_ms: get_metric_value(:average_duration_ms, time_window, tenant_id, effect_type),
      p95_duration_ms: get_metric_value(:p95_duration_ms, time_window, tenant_id, effect_type),
      p99_duration_ms: get_metric_value(:p99_duration_ms, time_window, tenant_id, effect_type),
      success_rate: calculate_success_rate(time_window, tenant_id, effect_type),
      error_rate: calculate_error_rate(time_window, tenant_id, effect_type),
      throughput_per_second: calculate_throughput(time_window, tenant_id, effect_type),
      top_effect_types: get_top_effect_types(time_window, tenant_id),
      top_error_reasons: get_top_error_reasons(time_window, tenant_id, effect_type)
    }
  end

  @doc """
  Gets performance insights and recommendations.
  """
  @spec get_performance_insights(keyword()) :: map()
  def get_performance_insights(opts \\ []) do
    metrics = get_execution_metrics(opts)

    insights = %{
      performance_status: determine_performance_status(metrics),
      bottlenecks: identify_bottlenecks(metrics),
      recommendations: generate_recommendations(metrics),
      trends: analyze_trends(metrics),
      capacity_analysis: analyze_capacity(metrics)
    }

    insights
  end

  @doc """
  Generates a performance report for a specific time period.
  """
  @spec generate_performance_report(keyword()) :: String.t()
  def generate_performance_report(opts \\ []) do
    metrics = get_execution_metrics(opts)
    insights = get_performance_insights(opts)

    """
    # FSM Effects Performance Report
    Generated: #{DateTime.utc_now() |> DateTime.to_string()}
    Time Window: #{Keyword.get(opts, :time_window, 300_000)} ms

    ## Overview
    - Total Executions: #{metrics.total_executions}
    - Success Rate: #{Float.round(metrics.success_rate * 100, 2)}%
    - Error Rate: #{Float.round(metrics.error_rate * 100, 2)}%
    - Average Duration: #{Float.round(metrics.average_duration_ms, 2)} ms
    - Throughput: #{Float.round(metrics.throughput_per_second, 2)} effects/sec

    ## Performance Status
    #{insights.performance_status}

    ## Top Effect Types
    #{format_top_items(metrics.top_effect_types)}

    ## Top Error Reasons
    #{format_top_items(metrics.top_error_reasons)}

    ## Recommendations
    #{format_recommendations(insights.recommendations)}

    ## Bottlenecks Identified
    #{format_bottlenecks(insights.bottlenecks)}
    """
  end

  # Private Functions

  defp handle_telemetry_event([:fsm, :effect, :started], measurements, metadata, _config) do
    Logger.debug("Effect started: #{metadata.effect_type} [#{metadata.execution_id}]",
      measurements: measurements, metadata: metadata)

    # Store metrics for aggregation
    store_metric(:effect_started, metadata.effect_type, measurements, metadata)
  end

  defp handle_telemetry_event([:fsm, :effect, :completed], measurements, metadata, _config) do
    Logger.debug("Effect completed: #{metadata.effect_type} [#{metadata.execution_id}] in #{measurements.duration_us}μs",
      measurements: measurements, metadata: metadata)

    # Store metrics and update performance data
    store_metric(:effect_completed, metadata.effect_type, measurements, metadata)
    update_performance_metrics(:success, metadata.effect_type, measurements.duration_us)
  end

  defp handle_telemetry_event([:fsm, :effect, :failed], measurements, metadata, _config) do
        Logger.warning("Effect failed: #{metadata.effect_type} [#{metadata.execution_id}] - #{inspect(metadata.error)}",
      measurements: measurements, metadata: metadata)

    # Store error metrics
    store_metric(:effect_failed, metadata.effect_type, measurements, metadata)
    update_performance_metrics(:failure, metadata.effect_type, 0)
    record_error_reason(metadata.effect_type, metadata.error)
  end

  defp handle_telemetry_event([:fsm, :effect, :cancelled], measurements, metadata, _config) do
    Logger.info("Effect cancelled: #{metadata.effect_type} [#{metadata.execution_id}] - #{metadata.cancellation_reason}",
      measurements: measurements, metadata: metadata)

    store_metric(:effect_cancelled, metadata.effect_type, measurements, metadata)
    update_performance_metrics(:cancelled, metadata.effect_type, 0)
  end

  defp handle_telemetry_event([:fsm, :effect, :timeout], measurements, metadata, _config) do
        Logger.warning("Effect timeout: #{metadata.effect_type} [#{metadata.execution_id}] after #{metadata.timeout_ms}ms",
      measurements: measurements, metadata: metadata)

    store_metric(:effect_timeout, metadata.effect_type, measurements, metadata)
    update_performance_metrics(:timeout, metadata.effect_type, metadata.timeout_ms * 1000)
  end

  defp handle_telemetry_event([:fsm, :effect, :retry], measurements, metadata, _config) do
    Logger.info("Effect retry: #{metadata.effect_type} [#{metadata.execution_id}] attempt #{metadata.attempt}/#{metadata.max_attempts}",
      measurements: measurements, metadata: metadata)

    store_metric(:effect_retry, metadata.effect_type, measurements, metadata)
  end

  defp handle_telemetry_event([:fsm, :effect, :circuit_breaker], measurements, metadata, _config) do
        Logger.warning("Circuit breaker state change: #{metadata.breaker_id} #{metadata.old_state} -> #{metadata.new_state}",
      measurements: measurements, metadata: metadata)

    store_metric(:circuit_breaker_event, :circuit_breaker, measurements, metadata)
  end

  defp handle_telemetry_event([:fsm, :effect, :composition], measurements, metadata, _config) do
    Logger.debug("Composition executed: #{metadata.composition_type} with #{metadata.effect_count} effects in #{measurements.duration_us}μs",
      measurements: measurements, metadata: metadata)

    store_metric(:composition_executed, metadata.composition_type, measurements, metadata)
  end

  # Metrics storage and retrieval (simplified implementation)
  # In production, these would integrate with a metrics store like Prometheus, InfluxDB, etc.

  defp store_metric(event_type, effect_type, measurements, metadata) do
    # Store in ETS table or send to metrics backend
    # This is a placeholder implementation
    :persistent_term.put(
      {:fsm_effects_metric, event_type, effect_type, System.system_time(:millisecond)},
      %{measurements: measurements, metadata: metadata}
    )
  end

  defp get_metric_value(metric_name, _time_window, _tenant_id, _effect_type) do
    # Placeholder implementation - would query actual metrics store
    case metric_name do
      :total_executions -> 1000
      :successful_executions -> 950
      :failed_executions -> 30
      :cancelled_executions -> 15
      :timeout_executions -> 5
      :average_duration_ms -> 150.5
      :p95_duration_ms -> 500.2
      :p99_duration_ms -> 1200.8
      _ -> 0
    end
  end

  defp update_performance_metrics(_outcome, _effect_type, _duration_us) do
    # Update running performance metrics
    # Placeholder implementation
    :ok
  end

  defp record_error_reason(_effect_type, _error) do
    # Record error for analysis
    # Placeholder implementation
    :ok
  end

  defp calculate_success_rate(time_window, tenant_id, effect_type) do
    total = get_metric_value(:total_executions, time_window, tenant_id, effect_type)
    successful = get_metric_value(:successful_executions, time_window, tenant_id, effect_type)

    if total > 0 do
      successful / total
    else
      0.0
    end
  end

  defp calculate_error_rate(time_window, tenant_id, effect_type) do
    1.0 - calculate_success_rate(time_window, tenant_id, effect_type)
  end

  defp calculate_throughput(time_window, tenant_id, effect_type) do
    total = get_metric_value(:total_executions, time_window, tenant_id, effect_type)
    window_seconds = time_window / 1000

    total / window_seconds
  end

  defp get_top_effect_types(_time_window, _tenant_id) do
    # Return top effect types by volume
    [
      {:call_llm, 450},
      {:coordinate_agents, 200},
      {:sequence, 180},
      {:parallel, 120},
      {:rag_pipeline, 50}
    ]
  end

  defp get_top_error_reasons(_time_window, _tenant_id, _effect_type) do
    # Return top error reasons
    [
      {:timeout, 15},
      {:llm_error, 10},
      {:network_error, 3},
      {:validation_failed, 2}
    ]
  end

  defp determine_performance_status(metrics) do
    cond do
      metrics.success_rate >= 0.99 and metrics.average_duration_ms < 100 ->
        "🟢 Excellent - High success rate and low latency"

      metrics.success_rate >= 0.95 and metrics.average_duration_ms < 500 ->
        "🟡 Good - Acceptable performance with room for improvement"

      metrics.success_rate >= 0.90 ->
        "🟠 Warning - Success rate below optimal threshold"

      true ->
        "🔴 Critical - Performance issues require immediate attention"
    end
  end

  defp identify_bottlenecks(metrics) do
    bottlenecks = []

    bottlenecks = if metrics.p95_duration_ms > 1000 do
      ["High P95 latency indicates occasional slow effects" | bottlenecks]
    else
      bottlenecks
    end

    bottlenecks = if metrics.error_rate > 0.1 do
      ["High error rate suggests reliability issues" | bottlenecks]
    else
      bottlenecks
    end

    bottlenecks = if metrics.throughput_per_second < 10 do
      ["Low throughput may indicate resource constraints" | bottlenecks]
    else
      bottlenecks
    end

    bottlenecks
  end

  defp generate_recommendations(metrics) do
    recommendations = []

    recommendations = if metrics.average_duration_ms > 200 do
      ["Consider implementing effect result caching for better performance" | recommendations]
    else
      recommendations
    end

    recommendations = if metrics.error_rate > 0.05 do
      ["Implement circuit breakers for unreliable external services" | recommendations]
    else
      recommendations
    end

    recommendations = if metrics.timeout_executions > metrics.total_executions * 0.01 do
      ["Review and adjust timeout values for better reliability" | recommendations]
    else
      recommendations
    end

    recommendations
  end

  defp analyze_trends(_metrics) do
    # Placeholder for trend analysis
    %{
      performance_trend: :stable,
      volume_trend: :increasing,
      error_trend: :decreasing
    }
  end

  defp analyze_capacity(_metrics) do
    # Placeholder for capacity analysis
    %{
      current_utilization: 0.65,
      projected_capacity: :adequate,
      scaling_recommendation: :none
    }
  end

  defp format_top_items(items) do
    items
    |> Enum.map(fn {name, count} -> "- #{name}: #{count}" end)
    |> Enum.join("\n")
  end

  defp format_recommendations(recommendations) do
    recommendations
    |> Enum.with_index(1)
    |> Enum.map(fn {rec, idx} -> "#{idx}. #{rec}" end)
    |> Enum.join("\n")
  end

  defp format_bottlenecks(bottlenecks) do
    if length(bottlenecks) == 0 do
      "No significant bottlenecks identified."
    else
      bottlenecks
      |> Enum.with_index(1)
      |> Enum.map(fn {bottleneck, idx} -> "#{idx}. #{bottleneck}" end)
      |> Enum.join("\n")
    end
  end
end
