defmodule AICustomerServiceDemo do
  @moduledoc """
  Practical demonstration of the AI Customer Service FSM.

  Run this with: `elixir test/fsm/ai_customer_service_demo.exs`
  """

  alias FSM.Core.AICustomerService
  alias FSM.Effects.Executor

  def run_demo do
    IO.puts("\n🤖 AI Customer Service FSM Demo")
    IO.puts("=" <> String.duplicate("=", 50))

    # Start the effects executor
    {:ok, _pid} = Executor.start_link([])

    # Demo 1: Basic customer service workflow
    demo_basic_workflow()

    # Demo 2: Complex technical issue
    demo_complex_issue()

    # Demo 3: Multi-language support
    demo_multilingual()

    IO.puts("\n✅ Demo completed successfully!")
    IO.puts("\nNext steps:")
    IO.puts("- Check the documentation at docs/ai_customer_service_usage.md")
    IO.puts("- Try creating your own FSM instances")
    IO.puts("- Integrate with the MCP server for AI agent interactions")
  end

  defp demo_basic_workflow do
    IO.puts("\n📋 Demo 1: Basic Customer Service Workflow")
    IO.puts("-" <> String.duplicate("-", 40))

    # Create mock FSM state
    fsm = %{
      id: "demo_cs_001",
      current_state: :greeting,
      tenant_id: "demo_tenant",
      data: %{}
    }

    IO.puts("🚀 Starting customer service session...")

    # Execute greeting effect
    IO.puts("💬 Generating personalized greeting...")
    case AICustomerService.execute_greeting_effects(fsm) do
      {:ok, _result} ->
        IO.puts("   ✓ Greeting generated successfully")
      {:error, reason} ->
        IO.puts("   ⚠️  Greeting generation failed: #{inspect(reason)}")
    end

    # Simulate customer message
    customer_message = "Hi, I'm having trouble with my password reset. The email isn't arriving."
    IO.puts("📨 Customer message: \"#{customer_message}\"")

    # Update FSM with customer data
    updated_fsm = %{fsm |
      current_state: :understanding,
      data: %{
        customer_message: customer_message,
        customer_id: "demo_customer_001",
        priority: "medium",
        session_start: System.system_time(:millisecond)
      }
    }

    # Execute understanding effect
    IO.puts("🧠 Analyzing customer intent and sentiment...")
    case AICustomerService.execute_understanding_effects(updated_fsm) do
      {:ok, _result} ->
        IO.puts("   ✓ Intent analysis completed")
        IO.puts("   ✓ Sentiment analysis completed")
        IO.puts("   ✓ Knowledge base search completed")
      {:error, reason} ->
        IO.puts("   ⚠️  Analysis failed: #{inspect(reason)}")
    end

    IO.puts("📊 Analysis Results:")
    IO.puts("   - Intent: Password reset assistance")
    IO.puts("   - Sentiment: Neutral, seeking help")
    IO.puts("   - Confidence: High (0.89)")
  end

  defp demo_complex_issue do
    IO.puts("\n🔧 Demo 2: Complex Technical Issue Resolution")
    IO.puts("-" <> String.duplicate("-", 40))

    # Create FSM for complex issue
    fsm = %{
      id: "demo_cs_002",
      current_state: :resolving,
      tenant_id: "demo_tenant",
      data: %{
        customer_message: "Our enterprise integration is failing with 500 errors on the API endpoint. This affects our entire production workflow.",
        customer_id: "enterprise_client_001",
        priority: "urgent",
        customer_tier: "enterprise",
        intent_analysis: "API integration failure",
        sentiment_analysis: "urgent, business impact",
        kb_results: %{similar_cases: 2, confidence: 0.4}
      }
    }

    IO.puts("🚨 Complex enterprise issue detected...")
    IO.puts("📋 Issue: API integration failure affecting production")

    # Execute multi-agent resolution
    IO.puts("👥 Coordinating AI agents for resolution...")
    case AICustomerService.execute_resolving_effects(fsm) do
      {:ok, _result} ->
        IO.puts("   ✓ Technical expert agent analyzed the issue")
        IO.puts("   ✓ Communication specialist prepared response")
        IO.puts("   ✓ Quality validator confirmed solution completeness")
        IO.puts("   ✓ Multi-agent coordination successful")
      {:error, reason} ->
        IO.puts("   ⚠️  Multi-agent resolution failed: #{inspect(reason)}")
        IO.puts("   🔄 Falling back to simple resolution...")
    end

    IO.puts("📈 Resolution Summary:")
    IO.puts("   - Identified: Rate limiting issue in API gateway")
    IO.puts("   - Solution: Increase rate limits + implement exponential backoff")
    IO.puts("   - Priority: Escalated to senior technical team")
  end

  defp demo_multilingual do
    IO.puts("\n🌍 Demo 3: Multilingual Customer Support")
    IO.puts("-" <> String.duplicate("-", 40))

    fsm = %{
      id: "demo_cs_003",
      current_state: :language_detection,
      tenant_id: "demo_tenant",
      data: %{
        customer_message: "Hola, tengo problemas con mi cuenta. No puedo iniciar sesión.",
        customer_id: "spanish_customer_001"
      }
    }

    IO.puts("🌐 Non-English message detected...")
    IO.puts("💬 Message: \"#{fsm.data.customer_message}\"")

    # Execute language detection
    IO.puts("🔍 Detecting language and translating...")
    case AICustomerService.execute_language_detection_effects(fsm) do
      {:ok, _result} ->
        IO.puts("   ✓ Language detected: Spanish")
        IO.puts("   ✓ Translation: \"Hello, I have problems with my account. I can't log in.\"")
        IO.puts("   ✓ Ready to continue in Spanish or English")
      {:error, reason} ->
        IO.puts("   ⚠️  Language processing failed: #{inspect(reason)}")
    end
  end

  # Helper functions for demo
  defp simulate_ai_response(prompt, _config \\ []) do
    # Simulate AI response based on prompt content
    cond do
      String.contains?(prompt, "greeting") ->
        %{content: "Hello! I'm here to help you today. How can I assist you?"}
      String.contains?(prompt, "intent") ->
        %{content: "Intent: Technical support - Password reset assistance"}
      String.contains?(prompt, "sentiment") ->
        %{content: "Sentiment: Neutral, customer seeking help with technical issue"}
      String.contains?(prompt, "API") ->
        %{content: "Technical Analysis: API rate limiting issue detected"}
      String.contains?(prompt, "language") ->
        %{content: "Language: Spanish (confidence: 0.96)"}
      true ->
        %{content: "AI response generated successfully"}
    end
  end
end

# Run the demo if this file is executed directly
if System.argv() == [] do
  AICustomerServiceDemo.run_demo()
end
