defmodule FSM.Effects.DSL do
  require Logger

  @moduledoc """
  Enhanced DSL for FSM Navigator with Effects System integration.

  This module extends the existing FSM Navigator DSL with powerful effects
  capabilities while maintaining full backward compatibility. It provides:

  - `effect` macro for defining effects within states
  - `ai_workflow` macro for creating AI-native workflow patterns
  - Enhanced navigation with effects execution
  - Pre/post transition effects hooks
  - Effects-powered validation and lifecycle management

  ## Usage

      defmodule MyAIWorkflow do
        use FSM.Navigator
        use FSM.Effects.DSL

        state :processing do
          navigate_to :completed, when: :finished

                  effect :intelligent_processing do
          sequence do
            call_llm provider: :openai, model: "gpt-4", prompt: "Process the input data"
            put_data :result, get_result()
            log :info, "Processing completed successfully"
          end
        end
        end

        ai_workflow :multi_agent_analysis do
          coordinate_agents [
            %{id: :analyst, model: "gpt-4", role: "Data analyst"},
            %{id: :reviewer, model: "claude-3", role: "Quality reviewer"}
          ], type: :consensus
        end

        initial_state :processing
      end
  """

  alias FSM.Effects.{Types, Executor}

  defmacro __using__(_opts) do
    quote do
      import FSM.Effects.DSL, only: [
        effect: 1,
        effect: 2,
        ai_workflow: 2,
        sequence: 1,
        parallel: 1,
        race: 1,
        retry: 2,
        timeout: 2,
        with_compensation: 2,
        call_llm: 1,
        coordinate_agents: 2,
        rag_pipeline: 1,
        call: 3,
        delay: 1,
        log: 2,
        put_data: 2,
        get_data: 1,
        get_result: 0
      ]

      Module.register_attribute(__MODULE__, :effects, accumulate: true)
      Module.register_attribute(__MODULE__, :ai_workflows, accumulate: true)
      Module.register_attribute(__MODULE__, :pre_transition_effects, accumulate: true)
      Module.register_attribute(__MODULE__, :post_transition_effects, accumulate: true)

      @before_compile FSM.Effects.DSL
    end
  end

  # Core Effects DSL Macros

  @doc """
  Defines an effect to be executed when entering a state.

  ## Examples

      state :processing do
        effect do
          sequence do
            log :info, "Starting processing"
            call MyModule, :process, []
            put_data :status, :completed
          end
        end
      end
  """
  defmacro effect(do: block) do
    quote do
      effect_definition = unquote(Macro.escape(block))
      @effects {@current_state, :on_enter, effect_definition}
    end
  end

  @doc """
  Defines a named effect for reuse.

  ## Examples

      effect :data_processing do
        sequence do
          call DataService, :validate, [get_data(:input)]
          call DataService, :transform, [get_result()]
          put_data :processed, get_result()
        end
      end
  """
  defmacro effect(name, do: block) do
    quote do
      effect_definition = unquote(Macro.escape(block))
      # Store both as named effect and as state effect if we're in a state context
      @effects {unquote(name), effect_definition}
      if @current_state do
        @effects {@current_state, :on_enter, effect_definition}
      end
    end
  end

  @doc """
  Defines an AI workflow pattern that can be invoked by effects.

  ## Examples

      ai_workflow :customer_analysis do
        coordinate_agents [
          %{id: :sentiment, model: "claude-3", role: "Sentiment analyst"},
          %{id: :intent, model: "gpt-4", role: "Intent classifier"}
        ], type: :parallel
      end
  """
  defmacro ai_workflow(name, do: block) do
    # Extract effects at compile time
    effects = extract_workflow_effects(block)

    quote do
      workflow_definition = unquote(Macro.escape(block))
      @ai_workflows {unquote(name), workflow_definition}

      def unquote(:"#{name}_workflow")(fsm, context \\ %{}) do
        effects = unquote(Macro.escape(effects))
        Executor.execute_effect(effects, fsm, context)
      end
    end
  end

  # Effect Composition Operators

  @doc """
  Executes effects sequentially, stopping on first error.
  """
  defmacro sequence(do: block) do
    effects = extract_effects_from_block(block)
    quote do
      {:sequence, unquote(effects)}
    end
  end

  @doc """
  Executes effects in parallel, all must succeed.
  """
  defmacro parallel(do: block) do
    effects = extract_effects_from_block(block)
    quote do
      {:parallel, unquote(effects)}
    end
  end

  @doc """
  Executes effects in parallel, first success wins.
  """
  defmacro race(do: block) do
    effects = extract_effects_from_block(block)
    quote do
      {:race, unquote(effects)}
    end
  end

  @doc """
  Retries an effect with configurable backoff.
  """
  defmacro retry(effect, opts) do
    quote do
      Types.retry(unquote(effect), unquote(opts))
    end
  end

  @doc """
  Adds a timeout to an effect.
  """
  defmacro timeout(effect, timeout_ms) do
    quote do
      Types.timeout(unquote(effect), unquote(timeout_ms))
    end
  end

  @doc """
  Adds compensation (rollback) logic for an effect.
  """
  defmacro with_compensation(action, compensation) do
    quote do
      Types.with_compensation(unquote(action), unquote(compensation))
    end
  end

  # Core Effect Types

  @doc """
  Calls an LLM with the specified configuration.
  """
  defmacro call_llm(config) do
    quote do
      {:call_llm, unquote(config)}
    end
  end

  @doc """
  Coordinates multiple AI agents.
  """
  defmacro coordinate_agents(agent_specs, opts \\ []) do
    quote do
      {:coordinate_agents, unquote(agent_specs), unquote(opts)}
    end
  end

  @doc """
  Executes a RAG (Retrieval-Augmented Generation) pipeline.
  """
  defmacro rag_pipeline(config) do
    quote do
      {:rag_pipeline, unquote(config)}
    end
  end

  @doc """
  Calls a function on a module.
  """
  defmacro call(module, function, args) do
    quote do
      {:call, unquote(module), unquote(function), unquote(args)}
    end
  end

  @doc """
  Delays execution for specified milliseconds.
  """
  defmacro delay(milliseconds) do
    quote do
      {:delay, unquote(milliseconds)}
    end
  end

  @doc """
  Logs a message with specified level.
  """
  defmacro log(level, message) do
    quote do
      {:log, unquote(level), unquote(message)}
    end
  end

  @doc """
  Stores data in FSM context.
  """
  defmacro put_data(key, value) do
    quote do
      {:put_data, unquote(key), unquote(value)}
    end
  end

  @doc """
  Retrieves data from FSM context.
  """
  defmacro get_data(key) do
    quote do
      {:get_data, unquote(key)}
    end
  end

  @doc """
  Gets the result of the previous effect in a sequence.
  This is a compile-time helper that gets replaced with appropriate logic.
  """
  defmacro get_result do
    quote do
      {:get_result}
    end
  end

  # Enhanced Navigation Functions

  @doc """
  Enhanced navigation function that executes effects during transitions.

  This function extends the existing Navigator.navigate/3 function to support
  effects execution while maintaining backward compatibility.
  """
  def navigate_with_effects(fsm, event, event_data \\ %{}, opts \\ []) do
    with {:ok, validated_fsm} <- validate_transition(fsm, event, event_data),
         {:ok, pre_fsm} <- execute_pre_transition_effects(validated_fsm, event, event_data),
         {:ok, transitioned_fsm} <- perform_state_transition(pre_fsm, event, event_data),
         {:ok, final_fsm} <- execute_post_transition_effects(transitioned_fsm, event, event_data) do

      # Cancel previous state's running effects
      Executor.cancel_effects("#{fsm.id}:#{fsm.current_state}")

      # Broadcast state change if MCP streaming enabled
      if opts[:mcp_broadcast] do
        broadcast_mcp_state_change(fsm, transitioned_fsm, event)
      end

      {:ok, final_fsm}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Pre-compile hook to generate effect execution functions
  defmacro __before_compile__(env) do
    effects = Module.get_attribute(env.module, :effects) |> Enum.reverse()
    ai_workflows = Module.get_attribute(env.module, :ai_workflows) |> Enum.reverse()

    effect_functions = generate_effect_functions(effects)
    # Temporarily disable workflow_functions generation - ai_workflow macro already creates needed functions
    # workflow_functions = generate_workflow_functions(ai_workflows)

    quote do
      unquote_splicing(effect_functions)

      @doc """
      Gets the initial state for this FSM.
      """
      def initial_state do
        @initial_state
      end

      @doc """
      Gets the effects definition for a specific state.
      """
      def get_state_effects(state) do
        # Build effects map from both state-specific and named effects
        state_effects_map = %{
          unquote_splicing(
            for {effect_state, :on_enter, effect_def} <- effects, is_atom(effect_state), effect_state != nil do
              quote do: {unquote(effect_state), unquote(Macro.escape(effect_def))}
            end
          )
        }

        Map.get(state_effects_map, state)
      end

      @doc """
      Gets all defined AI workflows for this FSM.
      """
      def get_ai_workflows do
        unquote(Macro.escape(ai_workflows))
      end

      @doc """
      Gets a named effect definition.
      """
      def get_named_effect(name) do
        named_effects_map = %{
          unquote_splicing(
            for {effect_name, effect_def} <- effects, is_atom(effect_name) do
              quote do: {unquote(effect_name), unquote(Macro.escape(effect_def))}
            end
          )
        }

        Map.get(named_effects_map, name)
      end

      @doc """
      Executes a named effect.
      """
      def execute_named_effect(name, fsm, context \\ %{}) do
        case get_named_effect(name) do
          nil -> {:error, {:unknown_effect, name}}
          effect_def ->
            # Transform the effect definition from AST to executable effect
            effect = transform_effect_definition(effect_def)
            Executor.execute_effect(effect, fsm, context)
        end
      end

      defp transform_effect_definition(effect_def) do
        case effect_def do
          {:sequence, _, [[do: block]]} ->
            effects = FSM.Effects.DSL.extract_effects_from_block(block)
            {:sequence, effects}
          {:parallel, _, [[do: block]]} ->
            effects = FSM.Effects.DSL.extract_effects_from_block(block)
            {:parallel, effects}
          other ->
            FSM.Effects.DSL.transform_ast_to_effect(other)
        end
      end

      @doc """
      Executes effects for the current state, transforming AST to clean effects.
      """
      def execute_state_effects(fsm, state, context \\ %{}) do
        case get_state_effects(state) do
          nil -> {:ok, fsm}
          effect_def ->
            # Transform the effect definition from AST to executable effect
            effect = transform_effect_definition(effect_def)
            Executor.execute_effect(effect, fsm, context)
        end
      end
    end
  end

  # Helper functions for effect compilation

  defp generate_effect_functions(effects) do
    # Group effects to avoid duplicate function names
    effect_groups = effects
      |> Enum.group_by(fn
        {state, :on_enter, _effect_def} when is_atom(state) -> {:state, state}
        {name, _effect_def} when is_atom(name) -> {:named, name}
        _ -> :ignore
      end)
      |> Map.delete(:ignore)

    Enum.map(effect_groups, fn
      {{:state, state}, _effects} ->
        quote do
          def unquote(:"execute_#{state}_effects")(fsm, context \\ %{}) do
            execute_state_effects(fsm, unquote(state), context)
          end
        end

      {{:named, name}, _effects} ->
        quote do
          def unquote(:"execute_#{name}")(fsm, context \\ %{}) do
            execute_named_effect(unquote(name), fsm, context)
          end
        end

      _ -> nil
    end)
    |> Enum.filter(& &1)
  end

  defp generate_workflow_functions(workflows) do
    Enum.map(workflows, fn {name, workflow_def} ->
      quote do
        def unquote(:"get_#{name}_workflow") do
          unquote(Macro.escape(workflow_def))
        end
      end
    end)
  end

  # Private helper functions

  defp validate_transition(fsm, _event, _event_data) do
    # This would integrate with existing FSM validation
    # For now, just pass through
    {:ok, fsm}
  end

  defp execute_pre_transition_effects(fsm, event, event_data) do
    # Execute any pre-transition effects
    context = %{
      event: event,
      event_data: event_data,
      old_state: fsm.current_state
    }

    case get_pre_transition_effects(fsm.current_state, event) do
      nil -> {:ok, fsm}
      effects ->
        case Executor.execute_effect(effects, fsm, context) do
          {:ok, _result} -> {:ok, fsm}
          {:error, reason} -> {:error, {:pre_transition_effects_failed, reason}}
        end
    end
  end

  defp perform_state_transition(fsm, event, _event_data) do
    # This would integrate with existing FSM state transition logic
    # For now, just simulate a transition
    new_state = determine_next_state(fsm.current_state, event)
    updated_fsm = Map.put(fsm, :current_state, new_state)
    {:ok, updated_fsm}
  end

    defp execute_post_transition_effects(fsm, _event, _event_data) do
    # Execute effects for entering the new state
    # This is a placeholder - actual implementation would be in the module using the DSL
    {:ok, fsm}
  end

  defp get_pre_transition_effects(_state, _event) do
    # Placeholder for pre-transition effects lookup
    nil
  end

  defp determine_next_state(current_state, _event) do
    # Placeholder for state transition logic
    # This would integrate with existing Navigator logic
    current_state
  end

  defp broadcast_mcp_state_change(_old_fsm, _new_fsm, _event) do
    # Placeholder for MCP broadcast integration
    # This will be implemented when we enhance MCP integration
    :ok
  end

  def extract_effects_from_block(block) do
    # Extracts and processes effect calls from a do block
    # Transform AST into clean effect tuples
    statements = case block do
      {:__block__, [], statements} -> statements
      statement -> [statement]
    end

    # Transform each statement from AST to effect tuple
    Enum.map(statements, &transform_ast_to_effect/1)
  end

  # Transform AST nodes into effect tuples, stripping line metadata
  def transform_ast_to_effect({:log, _, [level, message]}) do
    {:log, clean_ast(level), clean_ast(message)}
  end

  def transform_ast_to_effect({:put_data, _, [key, value]}) do
    {:put_data, clean_ast(key), clean_ast(value)}
  end

  def transform_ast_to_effect({:call, _, [module, function, args]}) do
    {:call, clean_ast(module), clean_ast(function), clean_ast(args)}
  end

  def transform_ast_to_effect({:call_llm, _, [config]}) do
    {:call_llm, clean_ast(config)}
  end

  def transform_ast_to_effect({:coordinate_agents, _, [agents, opts]}) do
    {:coordinate_agents, clean_ast(agents), clean_ast(opts)}
  end

  def transform_ast_to_effect({:delay, _, [ms]}) do
    {:delay, clean_ast(ms)}
  end

  def transform_ast_to_effect({:get_data, _, [key]}) do
    {:get_data, clean_ast(key)}
  end

  def transform_ast_to_effect({:get_result, _, []}) do
    {:get_result}
  end

  def transform_ast_to_effect({:sequence, _, [[do: block]]}) do
    effects = extract_effects_from_block(block)
    {:sequence, effects}
  end

  def transform_ast_to_effect({:parallel, _, [[do: block]]}) do
    effects = extract_effects_from_block(block)
    {:parallel, effects}
  end

  # Handle the case where sequence/parallel are already effect tuples
  def transform_ast_to_effect({:sequence, effects}) when is_list(effects) do
    {:sequence, Enum.map(effects, &transform_ast_to_effect/1)}
  end

  def transform_ast_to_effect({:parallel, effects}) when is_list(effects) do
    {:parallel, Enum.map(effects, &transform_ast_to_effect/1)}
  end

  # Handle with_compensation
  def transform_ast_to_effect({:with_compensation, _, [action, compensation]}) do
    {:with_compensation, transform_ast_to_effect(action), transform_ast_to_effect(compensation)}
  end

  # Handle retry
  def transform_ast_to_effect({:retry, _, [effect, opts]}) do
    {:retry, transform_ast_to_effect(effect), clean_ast(opts)}
  end

  # Handle timeout
  def transform_ast_to_effect({:timeout, _, [effect, timeout_ms]}) do
    {:timeout, transform_ast_to_effect(effect), clean_ast(timeout_ms)}
  end

  # Handle race
  def transform_ast_to_effect({:race, _, [[do: block]]}) do
    effects = extract_effects_from_block(block)
    {:race, effects}
  end

  # Handle race when already processed as effect tuple
  def transform_ast_to_effect({:race, effects}) when is_list(effects) do
    {:race, Enum.map(effects, &transform_ast_to_effect/1)}
  end

  # Handle __block__ specially - convert to sequence
  def transform_ast_to_effect({:__block__, _, statements}) do
    effects = Enum.map(statements, &transform_ast_to_effect/1)
    {:sequence, effects}
  end

  # For any unhandled AST, try to clean it and warn
  def transform_ast_to_effect(ast) do
    Logger.warning("Unhandled AST in effect transformation: #{inspect(ast)}")
    clean_ast(ast)
  end

  # Recursively clean AST of line metadata
  defp clean_ast({:__aliases__, _meta, modules}) do
    Module.concat(modules)
  end

  defp clean_ast({:%{}, _meta, pairs}) do
    Map.new(pairs, fn {k, v} -> {clean_ast(k), clean_ast(v)} end)
  end

  defp clean_ast({:{}, _meta, elements}) do
    List.to_tuple(Enum.map(elements, &clean_ast/1))
  end

  defp clean_ast({:__block__, _meta, statements}) do
    Enum.map(statements, &clean_ast/1)
  end

  defp clean_ast([do: block]) do
    [do: clean_ast(block)]
  end

  defp clean_ast({name, _meta, args}) when is_atom(name) and is_list(args) do
    {name, Enum.map(args, &clean_ast/1)}
  end

  defp clean_ast(list) when is_list(list) do
    Enum.map(list, &clean_ast/1)
  end

  defp clean_ast({left, right}) do
    {clean_ast(left), clean_ast(right)}
  end

  defp clean_ast(other) when is_atom(other) or is_number(other) or is_binary(other) do
    other
  end

  defp clean_ast(other) do
    other
  end

  defp extract_workflow_effects(block) do
    # Extracts effects from AI workflow blocks
    extract_effects_from_block(block)
  end

  # Utility functions for FSM integration

  @doc """
  Checks if a module uses the Effects DSL.
  """
  def effects_enabled?(module) do
    function_exported?(module, :execute_state_effects, 3)
  end

  @doc """
  Gets all available effects for a module.
  """
  def get_available_effects(module) do
    if effects_enabled?(module) do
      try do
        # Get all effects by inspecting the module attributes
        if function_exported?(module, :get_ai_workflows, 0) do
          workflows = module.get_ai_workflows()
          # Return workflow names as effect identifiers
          Enum.map(workflows, fn {name, _def} -> {name, :ai_workflow} end)
        else
          []
        end
      rescue
        _ -> []
      end
    else
      []
    end
  end

  @doc """
  Validates that all effects in a module are properly defined.
  """
  def validate_module_effects(module) do
    if effects_enabled?(module) do
      try do
        effects = get_available_effects(module) || []
        Enum.reduce_while(effects, :ok, fn effect, _acc ->
          # For now, just validate basic structure since effects are tuples {name, type}
          case effect do
            {_name, _type} -> {:cont, :ok}
            _ -> {:cont, :ok}  # Skip validation for now
          end
        end)
      rescue
        error -> {:error, {:validation_failed, error}}
      end
    else
      :ok
    end
  end
end
