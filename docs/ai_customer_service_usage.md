# AI Customer Service FSM Usage Guide

## Overview

The AI Customer Service FSM (`FSM.Core.AICustomerService`) is a comprehensive demonstration of the Effects System that provides intelligent, multi-agent customer service workflows with real-time AI processing.

## FSM States & Workflow

```
greeting → understanding → resolving → quality_check → response_ready → completed
    ↓           ↓             ↓            ↓               ↓
language_detection   clarifying     escalating     learning    human_handoff
                         ↓             ↓                           ↓
                   understanding   human_handoff           callback_scheduled
```

## Usage Methods

### Method 1: Via MCP (Recommended for AI Agents)

#### 1. Create AI Workflow
```json
{
  "tool": "create_ai_workflow",
  "arguments": {
    "template": "customer_service", 
    "config": {
      "department": "technical_support",
      "escalation_threshold": 0.8,
      "languages": ["en", "es"],
      "max_resolution_time": 300000
    },
    "tenant_id": "your_tenant_id"
  }
}
```

#### 2. Send Customer Message
```json
{
  "tool": "send_event",
  "arguments": {
    "fsm_id": "returned_fsm_id_from_step_1",
    "event": "customer_message",
    "event_data": {
      "message": "My app keeps crashing when I try to save files",
      "customer_id": "cust_12345", 
      "priority": "medium",
      "channel": "web_chat",
      "timestamp": "2024-01-15T10:30:00Z"
    }
  }
}
```

#### 3. Monitor Progress (Optional)
```json
{
  "tool": "stream_fsm_events",
  "arguments": {
    "fsm_id": "your_fsm_id",
    "event_types": ["state_changed", "effect_completed"]
  }
}
```

### Method 2: Direct FSM Creation

#### 1. Create FSM Instance
```elixir
# Via FSM Manager
{:ok, fsm_id} = FSM.Manager.create_fsm(
  FSM.Core.AICustomerService,
  %{
    department: "technical_support",
    escalation_threshold: 0.8,
    languages: ["en"]
  },
  "your_tenant_id"
)
```

#### 2. Send Events
```elixir
# Send customer message
FSM.Manager.send_event(fsm_id, :customer_message, %{
  message: "I need help with my account settings",
  customer_id: "cust_67890",
  priority: "high"
})
```

## Required Event Data

### :customer_message Event

**Required Fields:**
```elixir
%{
  message: "Customer's message text",      # String - The customer's question/issue
  customer_id: "unique_customer_id"        # String - Customer identifier
}
```

**Optional Fields:**
```elixir
%{
  priority: "low|medium|high|urgent",      # String - Issue priority level
  channel: "web_chat|email|phone|app",     # String - Communication channel
  timestamp: "2024-01-15T10:30:00Z",       # String - ISO timestamp
  customer_tier: "basic|premium|vip",      # String - Customer tier for personalization
  previous_cases: [],                      # List - Previous support case references
  product_context: %{                      # Map - Product/feature context
    product: "mobile_app",
    version: "2.1.4",
    platform: "ios"
  },
  attachments: [],                         # List - File attachments (URLs or references)
  preferred_language: "en",                # String - Customer's preferred language
  urgency_indicators: [                    # List - Signals of urgency
    "system_down", 
    "payment_issue", 
    "security_concern"
  ]
}
```

### Other Events

#### :intent_clear
```elixir
%{
  confidence_score: 0.95,                  # Float - AI confidence in understanding
  resolution_path: "technical_solution"    # String - Chosen resolution approach
}
```

#### :intent_unclear  
```elixir
%{
  clarification_needed: [                  # List - What needs clarification
    "specific_error_message",
    "steps_to_reproduce"
  ],
  follow_up_questions: []                  # List - Generated follow-up questions
}
```

#### :complexity_high
```elixir
%{
  complexity_indicators: [                 # List - Why it's complex
    "multiple_systems_involved",
    "custom_integration",
    "compliance_requirements"
  ],
  required_expertise: ["database", "api"]  # List - Required specialist skills
}
```

#### :solution_provided
```elixir
%{
  solution_type: "step_by_step|documentation|escalation",
  confidence_score: 0.87,
  customer_feedback: "positive|negative|neutral"
}
```

## Complete Workflow Example

Here's a complete example showing the full customer service workflow:

```elixir
# 1. Start the workflow
{:ok, fsm_id} = FSM.Manager.create_fsm(
  FSM.Core.AICustomerService,
  %{department: "technical_support"},
  "acme_corp"
)

# 2. Customer sends initial message
FSM.Manager.send_event(fsm_id, :customer_message, %{
  message: "I can't log into my account. It says my password is wrong but I'm sure it's correct.",
  customer_id: "cust_98765",
  priority: "medium",
  channel: "web_chat",
  product_context: %{
    product: "web_app", 
    last_login: "2024-01-10T14:22:00Z"
  }
})

# 3. FSM automatically analyzes (no manual intervention needed)
# - AI classifies intent as "authentication_issue"
# - Sentiment analysis shows "frustrated but cooperative"
# - Knowledge base search finds similar cases

# 4. Multi-agent resolution begins automatically
# - Technical expert agent provides solution steps
# - Communication specialist formats user-friendly response  
# - Quality validator ensures completeness

# 5. Trigger quality check
FSM.Manager.send_event(fsm_id, :solution_provided, %{
  solution_type: "step_by_step",
  confidence_score: 0.92
})

# 6. System performs automatic quality validation
# If quality passes, moves to response_ready

# 7. Send response to customer
FSM.Manager.send_event(fsm_id, :response_sent, %{
  delivery_method: "web_chat",
  response_time: 45000  # 45 seconds
})

# 8. Optional: Trigger learning phase
FSM.Manager.send_event(fsm_id, :learn_from_interaction, %{
  customer_satisfaction: "positive",
  resolution_successful: true
})
```

## Advanced Usage Patterns

### Multilingual Support
```elixir
# For non-English messages
FSM.Manager.send_event(fsm_id, :non_english_detected, %{
  detected_language: "es",
  original_message: "Mi aplicación no funciona correctamente",
  confidence: 0.94
})

# After language processing
FSM.Manager.send_event(fsm_id, :language_identified, %{
  language: "es", 
  translated_message: "My application is not working correctly",
  continue_in_language: "es"  # or "en" for translation
})
```

### Escalation Scenarios
```elixir
# Trigger escalation to human agent
FSM.Manager.send_event(fsm_id, :complexity_high, %{
  complexity_indicators: ["custom_enterprise_setup", "legal_implications"],
  required_expertise: ["enterprise_solutions", "legal"],
  customer_tier: "enterprise"
})

# After agent assignment
FSM.Manager.send_event(fsm_id, :agent_assigned, %{
  agent_id: "agent_sarah_j",
  agent_expertise: ["enterprise_solutions"],
  estimated_wait_time: 120  # seconds
})
```

### Real-time Monitoring
```elixir
# Get current FSM state
{:ok, fsm} = FSM.Manager.get_fsm_state(fsm_id)
IO.inspect(fsm.current_state)  # Shows current state

# Get execution analytics
analytics = FSM.Effects.Telemetry.get_execution_metrics([
  fsm_id: fsm_id,
  time_window: 300_000  # Last 5 minutes
])
```

## Response Handling

The FSM stores all AI responses and analysis in its data. Access them via:

```elixir
{:ok, fsm} = FSM.Manager.get_fsm_state(fsm_id)

# Access AI analysis results
intent = fsm.data.intent_analysis
sentiment = fsm.data.sentiment_analysis  
solution = fsm.data.agent_results
quality_score = fsm.data.quality_score

# Session metadata
session_duration = fsm.data.session_duration
resolution_method = fsm.data.resolution_method
```

## Error Handling

The FSM includes built-in error handling:
- **Compensation effects**: Automatic fallback when AI agents fail
- **Timeout handling**: Prevents infinite waits
- **Retry logic**: Automatic retry for transient failures
- **Circuit breakers**: Protection against cascading failures

```elixir
# Monitor for errors
{:ok, fsm} = FSM.Manager.get_fsm_state(fsm_id)
case fsm.data.resolution_method do
  "fallback" -> 
    # Multi-agent resolution failed, used simple fallback
    IO.puts("Used fallback resolution")
  "multi_agent" ->
    # Full multi-agent workflow succeeded
    IO.puts("Full AI workflow completed")
end
```

## Integration with External Systems

### CRM Integration
```elixir
# The FSM can trigger external system updates
defmodule CRMIntegration do
  def update_case_status(customer_id, status, resolution) do
    # Your CRM API calls here
    {:ok, :updated}
  end
end

# Use in FSM event data
FSM.Manager.send_event(fsm_id, :solution_provided, %{
  solution_type: "resolved",
  trigger_crm_update: true,
  crm_data: %{
    case_status: "resolved",
    resolution_category: "technical_guidance"
  }
})
```

### Knowledge Base Updates
```elixir
# FSM learns from each interaction
FSM.Manager.send_event(fsm_id, :learn_from_interaction, %{
  update_kb: true,
  new_solution_pattern: %{
    problem_type: "authentication_failure",
    solution_steps: ["check_caps_lock", "password_reset", "clear_browser_cache"],
    success_rate: 0.89
  }
})
```

This comprehensive guide should help you effectively use the AI Customer Service FSM for building sophisticated, AI-powered customer service workflows!
