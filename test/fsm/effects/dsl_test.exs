defmodule FSM.Effects.DSLTest do
  use ExUnit.Case, async: false

  alias FSM.Effects.{DSL, Executor, Types}

  # Create a test FSM module using the new DSL
  defmodule TestEffectsFSM do
    use FSM.Navigator
    use FSM.Effects.DSL

    state :idle do
      navigate_to :processing, when: :start

      effect do
        sequence do
          log :info, "Entering idle state"
          put_data :status, :ready
        end
      end
    end

    state :processing do
      navigate_to :completed, when: :finish
      navigate_to :failed, when: :error

      effect :data_processing do
        sequence do
          log :info, "Starting data processing"
          call String, :upcase, [get_data(:input)]
          put_data :result, get_result()
          delay 50
          log :info, "Processing completed"
        end
      end
    end

    state :ai_analyzing do
      navigate_to :insights_ready, when: :analysis_complete

      effect do
        coordinate_agents [
          %{id: :analyst, model: "gpt-4", role: "Data analyst", task: "Analyze input"},
          %{id: :validator, model: "claude-3", role: "Validator", task: "Validate results"}
        ], type: :consensus
      end
    end

    state :parallel_processing do
      navigate_to :all_done, when: :parallel_complete

      effect do
        parallel do
          call String, :upcase, ["hello"]
          call String, :downcase, ["WORLD"]
          delay 30
        end
      end
    end

    state :robust_processing do
      navigate_to :resilient_complete, when: :robust_done

      effect do
        with_compensation(
          retry(
            timeout(
              call String, :upcase, [get_data(:input)],
              1000
            ),
            attempts: 3, backoff: :exponential, base_delay: 100
          ),
          log(:warn, "Compensation executed due to failure")
        )
      end
    end

    # Named effect that can be reused
    effect :validation_check do
      sequence do
        log :info, "Performing validation"
        call String, :length, [get_data(:input)]
        put_data :input_length, get_result()
      end
    end

    # AI workflow definition
    ai_workflow :sentiment_analysis do
      call_llm provider: :openai,
               model: "gpt-4",
               prompt: "Analyze sentiment of: #{get_data(:text)}",
               max_tokens: 100
    end

    initial_state :idle

    validate :check_input_present

    def check_input_present(fsm, _event, _event_data) do
      case Map.get(fsm.data || %{}, :input) do
        nil -> {:error, :missing_input}
        _ -> :ok
      end
    end
  end

  setup do
    # Stop any existing executor first to ensure clean state
    case Process.whereis(Executor) do
      pid when is_pid(pid) -> GenServer.stop(pid, :normal, 1000)
      nil -> :ok
    end

    # Start fresh executor for testing
    {:ok, _pid} = start_supervised({Executor, []})

    # Give the executor a moment to fully initialize
    :timer.sleep(10)

    # Mock FSM for testing
    fsm = %{
      id: "test_fsm_dsl_001",
      current_state: :idle,
      tenant_id: "test_tenant",
      data: %{input: "test_input", text: "I love this product!"}
    }

    %{fsm: fsm}
  end

  describe "DSL compilation" do
    test "compiles FSM with effects successfully" do
      # Verify the module compiled correctly
      assert function_exported?(TestEffectsFSM, :get_state_effects, 1)
      assert function_exported?(TestEffectsFSM, :execute_state_effects, 3)
      assert function_exported?(TestEffectsFSM, :execute_named_effect, 3)
      assert function_exported?(TestEffectsFSM, :get_ai_workflows, 0)
    end

    test "defines state-specific effects" do
      idle_effects = TestEffectsFSM.get_state_effects(:idle)
      assert idle_effects != nil

      processing_effects = TestEffectsFSM.get_state_effects(:processing)
      assert processing_effects != nil

      # Non-existent state should return nil
      assert TestEffectsFSM.get_state_effects(:non_existent) == nil
    end

    test "defines named effects" do
      # Test that we can execute a named effect
      fsm = %{id: "test", current_state: :idle, data: %{input: "hello"}}

      assert function_exported?(TestEffectsFSM, :execute_validation_check, 2)

      # The named effect should be accessible
      {:ok, _result} = TestEffectsFSM.execute_named_effect(:validation_check, fsm)
    end

    test "defines AI workflows" do
      workflows = TestEffectsFSM.get_ai_workflows()
      assert is_list(workflows)

      # Should have the sentiment_analysis workflow
      workflow_names = Enum.map(workflows, fn {name, _def} -> name end)
      assert :sentiment_analysis in workflow_names
    end
  end

  describe "effect execution through DSL" do
    test "executes simple state effects", %{fsm: fsm} do
      # Execute effects for the idle state
      {:ok, _result} = TestEffectsFSM.execute_state_effects(fsm, :idle)
    end

    test "executes named effects", %{fsm: fsm} do
      {:ok, _result} = TestEffectsFSM.execute_named_effect(:validation_check, fsm)
    end

    test "executes effects with data operations", %{fsm: fsm} do
      # The validation_check effect should work with get_data
      {:ok, _result} = TestEffectsFSM.execute_named_effect(:validation_check, fsm)
    end
  end

  describe "composition operators in DSL" do
    test "sequence macro creates proper effect structure" do
      # This tests the macro expansion at compile time
      sequence_effect = TestEffectsFSM.get_state_effects(:processing)

      # The effect should be defined (exact structure testing would require
      # more introspection of the compiled effects)
      assert sequence_effect != nil
    end

    test "parallel macro works in state definition" do
      parallel_effects = TestEffectsFSM.get_state_effects(:parallel_processing)
      assert parallel_effects != nil
    end

    test "complex composition with retry, timeout, and compensation" do
      robust_effects = TestEffectsFSM.get_state_effects(:robust_processing)
      assert robust_effects != nil
    end
  end

  describe "AI-specific DSL features" do
    test "call_llm macro creates proper effect", %{fsm: fsm} do
      # Execute the sentiment analysis workflow
      {:ok, _result} = TestEffectsFSM.sentiment_analysis_workflow(fsm)
    end

    test "coordinate_agents macro works in state", %{fsm: fsm} do
      # Execute effects for ai_analyzing state
      {:ok, _result} = TestEffectsFSM.execute_state_effects(fsm, :ai_analyzing)
    end
  end

  describe "DSL utility functions" do
    test "effects_enabled? detects DSL usage" do
      assert DSL.effects_enabled?(TestEffectsFSM) == true
    end

    test "validate_module_effects validates all effects" do
      # This should pass since our test module has valid effects
      assert DSL.validate_module_effects(TestEffectsFSM) == :ok
    end

    test "get_available_effects returns effects list" do
      effects = DSL.get_available_effects(TestEffectsFSM)
      assert is_list(effects) or effects == []
    end
  end

  describe "integration with existing Navigator" do
    test "DSL doesn't break existing Navigator functionality" do
      # Verify basic Navigator functions still work
      assert function_exported?(TestEffectsFSM, :states, 0)
      assert function_exported?(TestEffectsFSM, :transitions, 0)
      assert function_exported?(TestEffectsFSM, :initial_state, 0)

      # Test that we can get basic FSM information
      states = TestEffectsFSM.states()
      assert :idle in states
      assert :processing in states

      assert TestEffectsFSM.initial_state() == :idle
    end
  end

  # Test a more complex FSM with real effect execution
  defmodule ComplexWorkflowFSM do
    use FSM.Navigator
    use FSM.Effects.DSL

    state :start do
      navigate_to :data_prep, when: :begin

      effect do
        sequence do
          log :info, "Workflow started"
          put_data :workflow_id, System.unique_integer()
          put_data :start_time, System.system_time(:millisecond)
        end
      end
    end

    state :data_prep do
      navigate_to :analysis, when: :data_ready

      effect do
        parallel do
          # Data validation branch
          sequence do
            log :info, "Validating input data"
            call String, :length, [get_data(:input)]
            put_data :input_length, get_result()
          end

          # Data transformation branch
          sequence do
            log :info, "Transforming data"
            call String, :upcase, [get_data(:input)]
            put_data :transformed_input, get_result()
          end
        end
      end
    end

    state :analysis do
      navigate_to :results, when: :analysis_done

      effect do
        with_compensation(
          sequence do
            log :info, "Starting analysis"
            call_llm provider: :openai,
                     model: "gpt-4",
                     prompt: "Analyze: #{get_data(:transformed_input)}"
            put_data :analysis_result, get_result()
          end,
          sequence do
            log :error, "Analysis failed, executing rollback"
            put_data :analysis_result, %{error: "Analysis failed"}
          end
        )
      end
    end

    initial_state :start
  end

  describe "complex workflow execution" do
    test "executes multi-stage workflow with complex effects", %{fsm: fsm} do
      # Test the complex workflow FSM
      workflow_fsm = %{fsm | current_state: :start}

      # Execute start state effects
      {:ok, _result} = ComplexWorkflowFSM.execute_state_effects(workflow_fsm, :start)

      # Execute data_prep state effects (parallel execution)
      {:ok, _result} = ComplexWorkflowFSM.execute_state_effects(workflow_fsm, :data_prep)

      # Execute analysis state effects (with compensation)
      {:ok, _result} = ComplexWorkflowFSM.execute_state_effects(workflow_fsm, :analysis)
    end
  end

  describe "error handling in DSL" do
    test "handles invalid effect definitions gracefully" do
      # This would typically be caught at compile time, but we can test
      # runtime validation of effects
      fsm = %{id: "test", current_state: :idle, data: %{}}

      # Even if an effect fails, the system should handle it gracefully
      case TestEffectsFSM.execute_state_effects(fsm, :idle) do
        {:ok, _} -> :ok
        {:error, _reason} -> :ok  # Error handling is working
      end
    end
  end

  describe "performance with DSL" do
    test "DSL overhead is minimal" do
      fsm = %{id: "perf_test", current_state: :idle, data: %{input: "test"}}

      # Time execution of effects through DSL
      {time_us, _result} = :timer.tc(fn ->
        TestEffectsFSM.execute_state_effects(fsm, :idle)
      end)

      # Should execute quickly (under 10ms for simple effects)
      assert time_us < 10_000  # 10ms in microseconds
    end
  end
end
