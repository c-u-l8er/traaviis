defmodule FSM.Core.AICustomerService do
  @moduledoc """
  Demonstration FSM showcasing the new Effects System for AI-powered customer service.

  This FSM demonstrates:
  - Effects System integration
  - AI/LLM effects
  - Multi-agent coordination
  - Complex workflows with error handling
  - Real-time observability
  - MCP integration

  ## Usage Example via MCP

      # Create the workflow
      {
        "tool": "create_ai_workflow",
        "arguments": {
          "template": "customer_service",
          "config": {
            "department": "technical_support",
            "escalation_threshold": 0.8,
            "languages": ["en", "es"]
          }
        }
      }

      # Interact with the workflow
      {
        "tool": "send_event",
        "arguments": {
          "fsm_id": "cs_001",
          "event": "customer_message",
          "event_data": {
            "message": "My app keeps crashing when I try to save files",
            "customer_id": "cust_12345",
            "priority": "medium"
          }
        }
      }
  """

  use FSM.Navigator
  use FSM.Effects.DSL

  # Initial greeting and customer identification
  state :greeting do
    navigate_to :understanding, when: :customer_message
    navigate_to :language_detection, when: :non_english_detected

    effect :personalized_greeting do
      sequence do
        log :info, "AI Customer Service session started"
        put_data :session_start, System.system_time(:millisecond)

        # Generate personalized greeting based on customer history
        call_llm provider: :openai,
                 model: "gpt-4",
                 system: "You are a friendly, professional customer service representative",
                 prompt: "Generate a personalized greeting for customer service",
                 max_tokens: 150,
                 temperature: 0.7

        put_data :greeting_message, get_result()
        log :info, "Personalized greeting generated"
      end
    end
  end

  # Multi-modal intent analysis and sentiment detection
  state :understanding do
    navigate_to :resolving, when: :intent_clear
    navigate_to :clarifying, when: :intent_unclear
    navigate_to :escalating, when: :complexity_high

    effect :intelligent_analysis do
      parallel do
        # Intent classification
        sequence do
          call_llm provider: :openai,
                   model: "gpt-4",
                   system: "You are an expert at classifying customer service intents",
                   prompt: "Classify the intent of this message: #{get_data(:customer_message)}",
                   max_tokens: 200
          put_data :intent_analysis, get_result()
        end

        # Sentiment analysis
        sequence do
          call_llm provider: :anthropic,
                   model: "claude-3-sonnet",
                   system: "You are an expert at analyzing sentiment and emotional state",
                   prompt: "Analyze the sentiment and urgency of: #{get_data(:customer_message)}",
                   max_tokens: 200
          put_data :sentiment_analysis, get_result()
        end

        # Knowledge base search
        sequence do
          log :info, "Searching knowledge base for similar issues"
          # Placeholder for actual knowledge base search
          put_data :kb_results, %{similar_cases: [], confidence: 0.3}
        end
      end

      # Synthesize analysis results
      sequence do
        log :info, "Synthesizing analysis results"
        put_data :analysis_complete, true

        # Determine next action based on analysis
        call_llm provider: :openai,
                 model: "gpt-4",
                 system: "Based on the intent and sentiment analysis, determine the best course of action",
                 prompt: "Intent: #{get_data(:intent_analysis)}, Sentiment: #{get_data(:sentiment_analysis)}",
                 max_tokens: 300

        put_data :recommended_action, get_result()
      end
    end
  end

  # Multi-agent problem resolution
  state :resolving do
    navigate_to :quality_check, when: :solution_provided
    navigate_to :escalating, when: :resolution_failed
    navigate_to :followup_needed, when: :partial_resolution

    effect :intelligent_resolution do
      with_compensation(
        # Main resolution workflow
        sequence do
          log :info, "Beginning intelligent resolution process"

          # Multi-agent coordination for complex problem solving
          coordinate_agents [
            %{
              id: :technical_expert,
              model: "gpt-4",
              provider: :openai,
              role: "Senior Technical Support Specialist",
              system: "You are a senior technical support expert with deep product knowledge",
              task: "Provide technical solution for: #{get_data(:customer_message)}",
              context: %{
                intent: get_data(:intent_analysis),
                kb_results: get_data(:kb_results)
              }
            },
            %{
              id: :communication_specialist,
              model: "claude-3-sonnet",
              provider: :anthropic,
              role: "Customer Communication Expert",
              system: "You excel at explaining technical solutions in customer-friendly language",
              task: "Transform technical solution into clear customer communication",
              context: %{
                sentiment: get_data(:sentiment_analysis),
                customer_expertise: get_data(:customer_expertise, "beginner")
              }
            },
            %{
              id: :quality_validator,
              model: "gemini-pro",
              provider: :google,
              role: "Solution Quality Validator",
              system: "You validate solution quality and completeness",
              task: "Validate that the solution fully addresses the customer's issue",
              context: %{
                original_message: get_data(:customer_message)
              }
            }
          ],
          type: :sequential,
          success_criteria: "All agents agree the solution is complete and appropriate"

          put_data :agent_results, get_result()
          log :info, "Multi-agent resolution completed successfully"
        end,

        # Compensation: fallback to simple resolution
        sequence do
          log :warn, "Multi-agent resolution failed, falling back to simple resolution"

          call_llm provider: :openai,
                   model: "gpt-3.5-turbo",
                   system: "You are a helpful customer service representative",
                   prompt: "Provide a helpful response to: #{get_data(:customer_message)}",
                   max_tokens: 500

          put_data :fallback_solution, get_result()
          put_data :resolution_method, "fallback"
        end
      )
    end
  end

  # Quality assurance and response validation
  state :quality_check do
    navigate_to :response_ready, when: :quality_approved
    navigate_to :resolving, when: :quality_insufficient
    navigate_to :escalating, when: :quality_failed

    effect :quality_validation do
      race do
        # Quality validation with timeout
        timeout(
          sequence do
            log :info, "Performing quality validation"

            call_llm provider: :anthropic,
                     model: "claude-3-sonnet",
                     system: "You are a quality assurance specialist for customer service responses",
                     prompt: "Rate the quality of this customer service response on accuracy, helpfulness, and clarity: #{get_data(:agent_results)}",
                     max_tokens: 300

            put_data :quality_score, get_result()

            # Validate minimum quality threshold
            # In real implementation, this would parse the quality score
            put_data :quality_approved, true
          end,
          30_000  # 30 second timeout
        )

        # Fallback: automatic approval after delay
        sequence do
          delay 35_000  # Wait slightly longer than timeout
          put_data :quality_approved, true
          put_data :quality_method, "timeout_fallback"
        end
      end
    end
  end

  # Smart escalation with context preparation
  state :escalating do
    navigate_to :human_handoff, when: :agent_assigned
    navigate_to :callback_scheduled, when: :no_agents_available

    effect :smart_escalation do
      parallel do
        # Find best human agent
        sequence do
          log :info, "Finding optimal human agent for escalation"
          # Placeholder for agent matching service
          put_data :assigned_agent, %{
            id: "agent_001",
            name: "Sarah Johnson",
            expertise: ["technical", "billing"],
            availability: "immediate"
          }
        end

        # Prepare comprehensive handoff context
        sequence do
          call_llm provider: :openai,
                   model: "gpt-4",
                   system: "Create a comprehensive handoff summary for human agents",
                   prompt: "Summarize this customer service interaction for human agent handoff: Customer: #{get_data(:customer_message)}, Analysis: #{get_data(:intent_analysis)}, Attempted Resolution: #{get_data(:agent_results)}",
                   max_tokens: 800

          put_data :handoff_summary, get_result()
          log :info, "Handoff context prepared"
        end

        # Update customer with realistic expectations
        sequence do
          log :info, "Notifying customer of escalation"
          put_data :escalation_message, "Connecting you with a specialist who can provide personalized assistance..."
        end
      end
    end
  end

  # Continuous learning and improvement
  state :learning do
    navigate_to :completed, when: :learning_complete

    effect :continuous_improvement do
      parallel do
        # Interaction analysis for learning
        sequence do
          call_llm provider: :anthropic,
                   model: "claude-3-sonnet",
                   system: "Analyze customer service interactions to identify improvement opportunities",
                   prompt: "Analyze this customer service interaction for learning insights: #{get_conversation_summary()}",
                   max_tokens: 500

          put_data :learning_insights, get_result()
        end

        # Customer satisfaction prediction
        sequence do
          call_llm provider: :openai,
                   model: "gpt-4",
                   system: "Predict customer satisfaction based on interaction analysis",
                   prompt: "Predict customer satisfaction for this interaction: #{get_data(:quality_score)}",
                   max_tokens: 200

          put_data :satisfaction_prediction, get_result()
        end

        # Knowledge base updates
        sequence do
          log :info, "Updating knowledge base with new learnings"
          # Placeholder for knowledge base update
          put_data :kb_updated, true
        end
      end

      # Store learnings for future use
      sequence do
        log :info, "Storing interaction learnings"
        put_data :session_end, System.system_time(:millisecond)

        # Calculate session duration
        put_data :session_duration, get_data(:session_end) - get_data(:session_start)

        put_data :learning_complete, true
      end
    end
  end

  # Language detection and multilingual support
  state :language_detection do
    navigate_to :understanding, when: :language_identified

    effect :multilingual_processing do
      sequence do
        call_llm provider: :openai,
                 model: "gpt-4",
                 system: "You are an expert at language detection and translation",
                 prompt: "Detect the language of this text and provide an English translation if needed: #{get_data(:customer_message)}",
                 max_tokens: 300

        put_data :language_info, get_result()
        put_data :language_processed, true
      end
    end
  end

  # Final states
  state :response_ready do
    navigate_to :completed, when: :response_sent
    navigate_to :learning, when: :learn_from_interaction
  end

  state :human_handoff do
    navigate_to :completed, when: :handoff_complete
  end

  state :callback_scheduled do
    navigate_to :completed, when: :callback_confirmed
  end

  state :completed do
    # Terminal state
    navigate_to :learning, when: :post_analysis_requested

    effect :completion_summary do
      sequence do
        log :info, "Customer service session completed"

        # Generate completion summary
        call_llm provider: :openai,
                 model: "gpt-4",
                 system: "Generate a brief summary of this customer service interaction",
                 prompt: "Summarize the key outcomes of this customer service session",
                 max_tokens: 200

        put_data :session_summary, get_result()
        put_data :completion_time, System.system_time(:millisecond)

        log :info, "Session summary generated"
      end
    end
  end

  # Named effects for reuse
  effect :validate_customer do
    sequence do
      log :info, "Validating customer information"
      # Placeholder for customer validation
      put_data :customer_validated, true
    end
  end

  effect :update_case_status do
    sequence do
      log :info, "Updating case status in CRM"
      # Placeholder for CRM update
      put_data :case_updated, true
    end
  end

  # Named effect for sentiment monitoring (simplified to avoid macro issues)
  effect :monitor_sentiment do
    sequence do
      call_llm provider: :anthropic,
               model: "claude-3-haiku",  # Fast model for real-time monitoring
               prompt: "Monitor sentiment change during interaction",
               max_tokens: 100

      put_data :sentiment_trend, get_result()
    end
  end

  # Set initial state
  initial_state :greeting

  # Validation rules
  validate :check_customer_message_present
  validate :check_session_data_valid

  # Helper functions
  def check_customer_message_present(_fsm, _event, event_data) do
    case Map.get(event_data, :message) do
      nil -> {:error, :missing_customer_message}
      "" -> {:error, :empty_customer_message}
      _message -> :ok
    end
  end

  def check_session_data_valid(_fsm, _event, _event_data) do
    # Always valid for demo purposes
    :ok
  end

  defp get_conversation_summary do
    # In a real implementation, this would compile the conversation history
    "Customer reported technical issue, analyzed with multi-agent system, resolution provided"
  end
end
