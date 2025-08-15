defmodule FSM.Effects.Types do
  @moduledoc """
  Core effect type definitions for the FSM Effects System.

  This module defines all available effect types that can be used within FSM states
  to create declarative, composable workflows with powerful orchestration capabilities.

  ## Effect Categories

  - **Basic Operations**: call, delay, log, data operations
  - **FSM Operations**: invoke_fsm, spawn_fsm, send_event
  - **AI/LLM Operations**: call_llm, embed_text, vector_search, agent coordination
  - **Composition Operators**: sequence, parallel, race, retry, timeout, compensation
  - **Advanced Patterns**: saga, circuit_breaker, batch, cache, rate_limit
  """

  @typedoc """
  Core effect types that can be executed by the Effects System.
  """
  @type effect ::
    # Basic Operations
    {:call, module(), atom(), [any()]} |
    {:call, module(), atom(), [any()], keyword()} |
    {:call_api, String.t(), method(), map(), keyword()} |
    {:delay, non_neg_integer()} |
    {:log, log_level(), String.t()} |

    # Data Operations
    {:put_data, atom(), any()} |
    {:get_data, atom()} |
    {:merge_data, map()} |
    {:update_data, atom(), (any() -> any())} |
    {:delete_data, atom()} |

    # FSM Operations
    {:invoke_fsm, module(), atom(), map()} |
    {:spawn_fsm, module(), map(), keyword()} |
    {:send_event, fsm_id(), atom(), map()} |
    {:broadcast_event, atom(), map(), keyword()} |

    # AI/LLM Operations
    {:call_llm, llm_config()} |
    {:embed_text, String.t(), embed_config()} |
    {:vector_search, query(), search_config()} |
    {:invoke_agent, agent_id(), task()} |
    {:coordinate_agents, [agent_spec()], coordination_opts()} |
    {:rag_pipeline, rag_config()} |

    # Composition Operators
    {:sequence, [effect()]} |
    {:parallel, [effect()]} |
    {:race, [effect()]} |
    {:retry, effect(), retry_opts()} |
    {:timeout, effect(), non_neg_integer()} |
    {:with_compensation, effect(), effect()} |
    {:circuit_breaker, effect(), breaker_opts()} |

    # Advanced Patterns
    {:saga, [saga_step()]} |
    {:batch, [effect()], batch_opts()} |
    {:cache, effect(), cache_opts()} |
    {:rate_limit, effect(), rate_opts()} |

    # Conditional and Control Flow
    {:if_condition, boolean() | (() -> boolean()), effect(), effect()} |
    {:case_condition, any(), [{any(), effect()}]} |
    {:while_loop, (() -> boolean()), effect(), keyword()}

  @typedoc "HTTP methods for API calls"
  @type method :: :get | :post | :put | :patch | :delete | :head | :options

  @typedoc "Logging levels"
  @type log_level :: :debug | :info | :warn | :error

  @typedoc "FSM identifier"
  @type fsm_id :: String.t() | atom()

  @typedoc "Agent identifier"
  @type agent_id :: String.t() | atom()

  @typedoc "Task definition for agents"
  @type task :: String.t()

  @typedoc "Search query for vector operations"
  @type query :: String.t()

  @typedoc """
  Configuration for LLM calls with comprehensive options.
  """
  @type llm_config :: [
    provider: provider(),
    model: String.t(),
    prompt: String.t(),
    system: String.t() | nil,
    max_tokens: pos_integer(),
    temperature: float(),
    top_p: float() | nil,
    tools: [tool_spec()] | nil,
    timeout: pos_integer()
  ]

  @typedoc "LLM providers"
  @type provider :: :openai | :anthropic | :google | :local | :huggingface

  @typedoc "Tool specification for LLM function calling"
  @type tool_spec :: %{
    name: String.t(),
    description: String.t(),
    parameters: map()
  }

  @typedoc """
  Configuration for text embedding operations.
  """
  @type embed_config :: [
    provider: provider(),
    model: String.t() | nil,
    dimensions: pos_integer() | nil,
    timeout: pos_integer()
  ]

  @typedoc """
  Configuration for vector search operations.
  """
  @type search_config :: [
    index: String.t() | atom(),
    similarity_threshold: float(),
    top_k: pos_integer(),
    filters: map() | nil,
    rerank: boolean()
  ]

  @typedoc """
  Agent specification for multi-agent coordination.
  """
  @type agent_spec :: %{
    id: atom(),
    model: String.t(),
    provider: provider(),
    role: String.t(),
    system: String.t() | nil,
    task: String.t(),
    tools: [tool_spec()] | nil,
    context: map() | nil
  }

  @typedoc """
  Options for agent coordination patterns.
  """
  @type coordination_opts :: [
    type: coordination_type(),
    consensus_threshold: float(),
    max_iterations: pos_integer(),
    timeout: non_neg_integer(),
    success_criteria: String.t() | nil
  ]

  @typedoc "Types of agent coordination patterns"
  @type coordination_type ::
    :sequential | :parallel | :consensus | :debate | :hierarchical | :competitive

  @typedoc """
  Configuration for RAG (Retrieval-Augmented Generation) pipelines.
  """
  @type rag_config :: [
    query: String.t(),
    retrieval_strategy: retrieval_strategy(),
    knowledge_bases: [String.t()],
    max_context_tokens: pos_integer(),
    rerank: boolean(),
    fusion_method: fusion_method()
  ]

  @typedoc "RAG retrieval strategies"
  @type retrieval_strategy :: :semantic | :keyword | :hybrid | :graph_traversal

  @typedoc "Context fusion methods for RAG"
  @type fusion_method :: :concatenate | :rank_fusion | :weighted_combination

  @typedoc """
  Options for retry operations.
  """
  @type retry_opts :: [
    attempts: pos_integer(),
    backoff: backoff_strategy(),
    base_delay: pos_integer(),
    max_delay: pos_integer() | nil,
    jitter: boolean()
  ]

  @typedoc "Backoff strategies for retries"
  @type backoff_strategy :: :constant | :linear | :exponential | :fibonacci

  @typedoc """
  Options for circuit breaker pattern.
  """
  @type breaker_opts :: [
    failure_threshold: pos_integer(),
    timeout: pos_integer(),
    recovery_timeout: pos_integer(),
    expected_errors: [atom()] | :all
  ]

  @typedoc """
  Saga step definition for distributed transactions.
  """
  @type saga_step :: %{
    action: effect(),
    compensation: effect() | nil,
    timeout: pos_integer() | nil
  }

  @typedoc """
  Options for batch operations.
  """
  @type batch_opts :: [
    concurrency: pos_integer(),
    timeout: pos_integer(),
    fail_fast: boolean(),
    collect_results: boolean()
  ]

  @typedoc """
  Options for caching effects.
  """
  @type cache_opts :: [
    key: String.t() | (() -> String.t()),
    ttl: pos_integer(),
    namespace: String.t() | nil,
    invalidate_on: [atom()] | nil
  ]

  @typedoc """
  Options for rate limiting.
  """
  @type rate_opts :: [
    requests: pos_integer(),
    window: pos_integer(),
    algorithm: :token_bucket | :sliding_window | :fixed_window,
    burst_limit: pos_integer() | nil
  ]

  @typedoc """
  Effect execution context passed to effects.
  """
  @type effect_context :: %{
    fsm: map(),
    event: atom() | nil,
    event_data: map(),
    state: atom(),
    tenant_id: String.t(),
    execution_id: String.t(),
    metadata: map()
  }

  @typedoc """
  Result of effect execution.
  """
  @type effect_result ::
    {:ok, any()} |
    {:error, error_reason()} |
    {:cancelled, String.t()}

  @typedoc "Error reasons for effect execution"
  @type error_reason ::
    :timeout |
    :cancelled |
    :validation_failed |
    :circuit_breaker_open |
    :rate_limit_exceeded |
    {:llm_error, String.t()} |
    {:agent_error, String.t()} |
    {:network_error, String.t()} |
    {:custom_error, any()}

  # Helper functions for effect construction

  @doc """
  Creates a sequence effect that executes effects one after another.

  ## Examples

      sequence([
        {:log, :info, "Starting process"},
        {:call, MyModule, :process_data, []},
        {:put_data, :result, :success}
      ])
  """
  def sequence(effects) when is_list(effects), do: {:sequence, effects}

  @doc """
  Creates a parallel effect that executes effects concurrently.

  ## Examples

      parallel([
        {:call_llm, [provider: :openai, model: "gpt-4", prompt: "Analyze X"]},
        {:call_llm, [provider: :anthropic, model: "claude-3", prompt: "Review X"]},
        {:call, DataService, :fetch_metrics, []}
      ])
  """
  def parallel(effects) when is_list(effects), do: {:parallel, effects}

  @doc """
  Creates a race effect where the first successful effect wins.

  ## Examples

      race([
        {:call_llm, [provider: :openai, timeout: 5000]},
        {:call_llm, [provider: :anthropic, timeout: 7000]},
        {:call_llm, [provider: :local, timeout: 10000]}
      ])
  """
  def race(effects) when is_list(effects), do: {:race, effects}

  @doc """
  Creates a retry effect with exponential backoff.

  ## Examples

      retry(
        {:call_api, "https://api.example.com", :get, %{}, []},
        attempts: 3,
        backoff: :exponential,
        base_delay: 1000
      )
  """
  def retry(effect, opts \\ []), do: {:retry, effect, opts}

  @doc """
  Creates a timeout effect that cancels execution after specified time.

  ## Examples

      timeout(
        {:call_llm, [provider: :openai, prompt: "Complex analysis..."]},
        30_000
      )
  """
  def timeout(effect, timeout_ms), do: {:timeout, effect, timeout_ms}

  @doc """
  Creates a compensating effect for error recovery.

  ## Examples

      with_compensation(
        {:call, PaymentService, :charge, [amount]},
        {:call, PaymentService, :refund, [amount]}
      )
  """
  def with_compensation(action, compensation), do: {:with_compensation, action, compensation}

  @doc """
  Creates an LLM call effect with comprehensive configuration.

  ## Examples

      call_llm(
        provider: :openai,
        model: "gpt-4",
        prompt: "Analyze this data: [data would be interpolated here]",
        system: "You are an expert data analyst",
        max_tokens: 1000,
        temperature: 0.7
      )
  """
  def call_llm(config), do: {:call_llm, config}

  @doc """
  Creates an agent coordination effect.

  ## Examples

      coordinate_agents([
        %{id: :analyst, model: "gpt-4", role: "Data analyst", task: "Analyze trends"},
        %{id: :reviewer, model: "claude-3", role: "Quality reviewer", task: "Review analysis"}
      ], type: :consensus, consensus_threshold: 0.8)
  """
  def coordinate_agents(agent_specs, opts \\ []), do: {:coordinate_agents, agent_specs, opts}

  @doc """
  Creates a saga effect for distributed transaction management.

  ## Examples

      saga([
        %{action: {:call, OrderService, :create_order, []},
          compensation: {:call, OrderService, :cancel_order, []}},
        %{action: {:call, PaymentService, :charge, []},
          compensation: {:call, PaymentService, :refund, []}}
      ])
  """
  def saga(steps), do: {:saga, steps}

  @doc """
  Validates an effect definition for correctness.
  """
  @spec validate_effect(effect()) :: :ok | {:error, String.t()}
  def validate_effect({:sequence, effects}) when is_list(effects) do
    Enum.find_value(effects, :ok, &validate_effect/1)
  end

  def validate_effect({:parallel, effects}) when is_list(effects) do
    Enum.find_value(effects, :ok, &validate_effect/1)
  end

  def validate_effect({:call_llm, config}) when is_list(config) do
    required_keys = [:provider, :model, :prompt]
    missing_keys = Enum.filter(required_keys, fn key ->
      not Keyword.has_key?(config, key)
    end)

    if missing_keys == [] do
      :ok
    else
      {:error, "Missing required keys for call_llm: #{inspect(missing_keys)}"}
    end
  end

  def validate_effect({:coordinate_agents, agent_specs, _opts}) when is_list(agent_specs) do
    Enum.find_value(agent_specs, :ok, fn agent_spec ->
      required_keys = [:id, :model, :role, :task]
      missing_keys = Enum.filter(required_keys, fn key ->
        not Map.has_key?(agent_spec, key)
      end)

      if missing_keys == [] do
        :ok
      else
        {:error, "Missing required keys for agent: #{inspect(missing_keys)}"}
      end
    end)
  end

  def validate_effect(_effect), do: :ok

  @doc """
  Estimates the complexity score of an effect for resource allocation.
  """
  @spec complexity_score(effect()) :: :simple | :medium | :complex | :ai_intensive
  def complexity_score({:sequence, effects}), do:
    effects |> Enum.map(&complexity_score/1) |> Enum.max()

  def complexity_score({:parallel, _effects}), do: :complex

  def complexity_score({:call_llm, _config}), do: :ai_intensive

  def complexity_score({:coordinate_agents, _specs, _opts}), do: :ai_intensive

  def complexity_score({:rag_pipeline, _config}), do: :ai_intensive

  def complexity_score({:saga, _steps}), do: :complex

  def complexity_score(_effect), do: :simple
end
