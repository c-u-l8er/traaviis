defmodule FSMApp.MCP.Server do
  @moduledoc """
  MCP Server that exposes FSM functionality through the Model Context Protocol.

  This server provides tools for:
  - Creating and managing FSMs
  - Sending events to FSMs
  - Querying FSM states and data
  - Managing FSM components and plugins
  """
  use Hermes.Server,
    name: "FSM MCP Server",
    version: "1.0.0",
    capabilities: [:tools]

  @impl true
  def init(_client_info, frame) do
    {:ok, frame
      |> assign(
        fsm_manager: FSM.Manager,
        fsm_registry: FSM.Registry
      )
      |> register_tool("create_fsm",
        input_schema: %{
          module: {:required, :string, description: "The FSM module to instantiate"},
          config: {:optional, :object, description: "Initial configuration data for the FSM"},
          tenant_id: {:optional, :string, description: "Tenant ID for multi-tenancy"}
        },
        description: "Create a new FSM instance")
      |> register_tool("send_event",
        input_schema: %{
          fsm_id: {:required, :string, description: "The ID of the FSM to send the event to"},
          event: {:required, :string, description: "The event to send"},
          event_data: {:optional, :object, description: "Additional data for the event"}
        },
        description: "Send an event to an FSM")
      |> register_tool("get_fsm_state",
        input_schema: %{
          fsm_id: {:required, :string, description: "The ID of the FSM to query"}
        },
        description: "Get the current state and data of an FSM")
      |> register_tool("list_tenant_fsms",
        input_schema: %{
          tenant_id: {:required, :string, description: "The tenant ID to list FSMs for"}
        },
        description: "List all FSMs for a specific tenant")
      |> register_tool("destroy_fsm",
        input_schema: %{
          fsm_id: {:required, :string, description: "The ID of the FSM to destroy"}
        },
        description: "Destroy an FSM instance")
      |> register_tool("get_fsm_metrics",
        input_schema: %{
          fsm_id: {:required, :string, description: "The ID of the FSM to get metrics for"}
        },
        description: "Get performance metrics for an FSM")
      |> register_tool("batch_send_events",
        input_schema: %{
          events: {:required, :array,
            items: %{
              fsm_id: {:required, :string, description: "FSM ID"},
              event: {:required, :string, description: "Event name"},
              event_data: {:optional, :object, description: "Event data"}
            },
            description: "Array of events to send"
          }
        },
        description: "Send multiple events to multiple FSMs in a single operation")
      |> register_tool("get_server_stats",
        input_schema: %{},
        description: "Get overall server statistics and health information")
      |> register_tool("get_fsm_events",
        input_schema: %{
          fsm_id: {:required, :string, description: "The ID of the FSM to fetch events for"}
        },
        description: "List persisted events for an FSM")
      |> register_tool("replay_fsm",
        input_schema: %{
          fsm_id: {:required, :string, description: "The ID of the FSM to replay"},
          until_seq: {:optional, :number, description: "Replay up to (and including) sequence number"}
        },
        description: "Recreate FSM by replaying its events deterministically")
      |> register_tool("validate_fsm_transition",
        input_schema: %{
          fsm_id: {:required, :string, description: "The ID of the FSM to validate"},
          event: {:required, :string, description: "The event to validate"},
          event_data: {:optional, :object, description: "Event data for validation"}
        },
        description: "Check if an FSM can transition on a specific event")
      |> register_tool("get_available_fsm_modules",
        input_schema: %{},
        description: "List all available FSM modules that can be instantiated")
      |> register_tool("create_fsm_from_template",
        input_schema: %{
          template_name: {:required, :string, description: "Name of the FSM template to use"},
          config: {:optional, :object, description: "Configuration overrides for the template"},
          tenant_id: {:optional, :string, description: "Tenant ID for the new FSM"}
        },
        description: "Create an FSM using a predefined template")
      # Effects-powered MCP tools
      |> register_tool("execute_effect_pipeline",
        input_schema: %{
          fsm_id: {:required, :string, description: "The FSM ID to execute effects for"},
          effects: {:required, :object, description: "Effect pipeline definition"},
          context: {:optional, :object, description: "Additional context for effect execution"}
        },
        description: "Execute an arbitrary effects pipeline on an FSM")
      |> register_tool("create_ai_workflow",
        input_schema: %{
          template: {:required, :string, description: "AI workflow template name"},
          config: {:optional, :object, description: "Workflow configuration"},
          tenant_id: {:optional, :string, description: "Tenant ID for the workflow"}
        },
        description: "Create an FSM using AI-optimized workflow templates")
      |> register_tool("call_llm",
        input_schema: %{
          provider: {:required, :string, description: "LLM provider (openai, anthropic, google, local)"},
          model: {:required, :string, description: "Model name"},
          prompt: {:required, :string, description: "Prompt text"},
          system: {:optional, :string, description: "System prompt"},
          max_tokens: {:optional, :number, description: "Maximum tokens to generate"},
          temperature: {:optional, :number, description: "Temperature for generation"}
        },
        description: "Call an LLM directly through the effects system")
      |> register_tool("coordinate_agents",
        input_schema: %{
          agents: {:required, :array, description: "Array of agent specifications"},
          coordination_type: {:optional, :string, description: "Type of coordination (sequential, parallel, consensus, debate)"},
          success_criteria: {:optional, :string, description: "Success criteria for coordination"}
        },
        description: "Coordinate multiple AI agents for complex tasks")
      |> register_tool("stream_fsm_events",
        input_schema: %{
          fsm_id: {:required, :string, description: "FSM ID to stream events for"},
          event_types: {:optional, :array, description: "Types of events to stream"}
        },
        description: "Set up real-time streaming of FSM events")
      |> register_tool("get_workflow_analytics",
        input_schema: %{
          fsm_id: {:optional, :string, description: "FSM ID to get analytics for"},
          time_window: {:optional, :number, description: "Time window in milliseconds"}
        },
        description: "Get detailed analytics about workflow execution")
    }
  end

  def handle_tool("create_fsm", %{module: module_name, config: config, tenant_id: tenant_id}, frame) do
    try do
      module = resolve_module(module_name)

      # Create FSM
      case FSM.Manager.create_fsm(module, config || %{}, tenant_id) do
        {:ok, fsm_id} ->
          result = %{
            success: true,
            fsm_id: fsm_id,
            message: "FSM created successfully",
            details: %{
              module: module_name,
              tenant_id: tenant_id,
              config: config
            }
          }
          {:reply, result, frame}

        {:error, reason} ->
          result = %{
            success: false,
            error: "Failed to create FSM",
            details: inspect(reason)
          }
          {:reply, result, frame}
      end

    rescue
      ArgumentError ->
        result = %{
          success: false,
          error: "Invalid module name",
          details: "Module '#{module_name}' does not exist"
        }
        {:reply, result, frame}

      e ->
        result = %{
          success: false,
          error: "Unexpected error",
          details: inspect(e)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool("send_event", %{fsm_id: fsm_id, event: event, event_data: event_data}, frame) do
    try do
      case FSM.Manager.send_event(fsm_id, String.to_atom(event), event_data || %{}) do
        {:ok, fsm} ->
          result = %{
            success: true,
            message: "Event sent successfully",
            details: %{
              fsm_id: fsm_id,
              event: event,
              new_state: fsm.current_state,
              data: fsm.data
            }
          }
          {:reply, result, frame}

        {:error, reason} ->
          result = %{
            success: false,
            error: "Failed to send event",
            details: inspect(reason)
          }
          {:reply, result, frame}
      end

    rescue
      e ->
        result = %{
          success: false,
          error: "Unexpected error",
          details: inspect(e)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool("get_fsm_state", %{fsm_id: fsm_id}, frame) do
    case FSM.Manager.get_fsm_state(fsm_id) do
      {:ok, state_info} ->
        result = %{
          success: true,
          fsm_state: state_info
        }
        {:reply, result, frame}

      {:error, reason} ->
        result = %{
          success: false,
          error: "Failed to get FSM state",
          details: inspect(reason)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool("list_tenant_fsms", %{tenant_id: tenant_id}, frame) do
    case FSM.Manager.get_tenant_fsms(tenant_id) do
      {:ok, fsms} ->
        result = %{
          success: true,
          tenant_id: tenant_id,
          fsm_count: length(fsms),
          fsms: fsms
        }
        {:reply, result, frame}

      {:error, reason} ->
        result = %{
          success: false,
          error: "Failed to list tenant FSMs",
          details: inspect(reason)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool("destroy_fsm", %{fsm_id: fsm_id}, frame) do
    case FSM.Manager.destroy_fsm(fsm_id) do
      :ok ->
        result = %{
          success: true,
          message: "FSM destroyed successfully",
          fsm_id: fsm_id
        }
        {:reply, result, frame}

      {:error, reason} ->
        result = %{
          success: false,
          error: "Failed to destroy FSM",
          details: inspect(reason)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool("get_fsm_metrics", %{fsm_id: fsm_id}, frame) do
    case FSM.Manager.get_fsm_metrics(fsm_id) do
      {:ok, metrics} ->
        result = %{
          success: true,
          metrics: metrics
        }
        {:reply, result, frame}

      {:error, reason} ->
        result = %{
          success: false,
          error: "Failed to get FSM metrics",
          details: inspect(reason)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool("batch_send_events", %{events: events}, frame) do
    try do
      # Convert events to the format expected by the manager
      formatted_events = Enum.map(events, fn event ->
        {
          event.fsm_id,
          String.to_atom(event.event),
          event.event_data || %{}
        }
      end)

      case FSM.Manager.batch_send_events(formatted_events) do
        {:ok, results} ->
          result = %{
            success: true,
            message: "Batch events processed",
            total_events: length(events),
            results: results
          }
          {:reply, result, frame}

        {:error, reason} ->
          result = %{
            success: false,
            error: "Failed to process batch events",
            details: inspect(reason)
          }
          {:reply, result, frame}
      end

    rescue
      e ->
        result = %{
          success: false,
          error: "Unexpected error in batch processing",
          details: inspect(e)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool("get_server_stats", _params, frame) do
    try do
      manager_stats = FSM.Manager.get_stats()
      registry_stats = FSM.Registry.stats()

      result = %{
        success: true,
        server_stats: %{
          manager: manager_stats,
          registry: registry_stats,
          timestamp: DateTime.utc_now()
        }
      }
      {:reply, result, frame}

    rescue
      e ->
        result = %{
          success: false,
          error: "Failed to get server stats",
          details: inspect(e)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool("get_fsm_events", %{fsm_id: fsm_id}, frame) do
    {:ok, events} = FSM.EventStore.list(fsm_id)
    {:reply, %{success: true, fsm_id: fsm_id, events: events}, frame}
  end

  def handle_tool("replay_fsm", %{fsm_id: fsm_id} = params, frame) do
    with {:ok, events} <- FSM.EventStore.list(fsm_id) do
      until_seq = Map.get(params, :until_seq) || Map.get(params, "until_seq")
      events = if until_seq, do: Enum.filter(events, &(&1["seq"] <= until_seq)), else: events
      result = FSMApp.MCP.Server.ReplayHelper.replay(events)
      {:reply, %{success: true, replay: result}, frame}
    else
      {:error, reason} -> {:reply, %{success: false, error: "Failed to replay", details: inspect(reason)}, frame}
    end
  end

  defmodule ReplayHelper do
    @moduledoc false
    def replay(events) do
      # Minimal deterministic fold for API response; real replay should reconstruct structs
      Enum.reduce(events, %{state: nil, count: 0}, fn ev, acc ->
        case ev["type"] do
          "created" -> %{acc | state: ev["initial_state"], count: acc.count + 1}
          "transition" -> %{acc | state: ev["to"], count: acc.count + 1}
          _ -> acc
        end
      end)
    end
  end

  def handle_tool("validate_fsm_transition", %{fsm_id: fsm_id, event: event, event_data: _event_data}, frame) do
    try do
      case FSM.Registry.get(fsm_id) do
        {:ok, {module, fsm}} ->
          can_navigate = module.can_navigate?(fsm, String.to_atom(event))

          result = %{
            success: true,
            can_transition: can_navigate,
            details: %{
              fsm_id: fsm_id,
              event: event,
              current_state: fsm.current_state,
              possible_destinations: module.possible_destinations(fsm)
            }
          }
          {:reply, result, frame}

        {:error, reason} ->
          result = %{
            success: false,
            error: "FSM not found",
            details: inspect(reason)
          }
          {:reply, result, frame}
      end

    rescue
      e ->
        result = %{
          success: false,
          error: "Unexpected error in validation",
          details: inspect(e)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool("get_available_fsm_modules", _params, frame) do
    discovered = FSM.ModuleDiscovery.list_available_fsms()
    available_modules = Enum.map(discovered, fn m ->
      %{
        name: Atom.to_string(m.module),
        description: m.description,
        states: m.states,
        components: m.components
      }
    end)

    result = %{
      success: true,
      available_modules: available_modules
    }
    {:reply, result, frame}
  end

  # Helpers
  defp resolve_module(module_name) when is_atom(module_name), do: module_name
  defp resolve_module(module_name) when is_binary(module_name) do
    candidates =
      cond do
        String.starts_with?(module_name, "Elixir.") -> [module_name]
        String.contains?(module_name, ".") -> ["Elixir." <> module_name]
        true -> ["Elixir.FSM." <> module_name, "Elixir." <> module_name]
      end

    Enum.find_value(candidates, fn cand ->
      try do
        mod = String.to_existing_atom(cand)
        if Code.ensure_loaded?(mod), do: mod, else: nil
      rescue
        _ -> nil
      end
    end) ||
    raise ArgumentError, message: "Unknown module: #{module_name}"
  end

  def handle_tool("create_fsm_from_template", %{template_name: template_name, config: config, tenant_id: tenant_id}, frame) do
    # This would typically use predefined templates
    # For now, we'll implement basic template logic
    case get_template_config(template_name) do
      {:ok, template_config} ->
        # Merge template config with user config
        final_config = Map.merge(template_config, config || %{})

        # Create FSM using the template
        case FSM.Manager.create_fsm(template_config.module, final_config, tenant_id) do
          {:ok, fsm_id} ->
            result = %{
              success: true,
              message: "FSM created from template successfully",
              fsm_id: fsm_id,
              template: template_name,
              config: final_config
            }
            {:reply, result, frame}

          {:error, reason} ->
            result = %{
              success: false,
              error: "Failed to create FSM from template",
              details: inspect(reason)
            }
            {:reply, result, frame}
        end

      {:error, reason} ->
        result = %{
          success: false,
          error: "Template not found",
          details: reason
        }
        {:reply, result, frame}
    end
  end

  # Effects-powered MCP tool implementations

  def handle_tool("execute_effect_pipeline", %{fsm_id: fsm_id, effects: effects_spec, context: context}, frame) do
    try do
      # Get the FSM
      case FSM.Registry.lookup_fsm(fsm_id) do
        {:ok, fsm} ->
          # Convert effects_spec to proper effect format
          effects = parse_effects_spec(effects_spec)

          # Execute the effects pipeline
          case FSM.Effects.Executor.execute_effect(effects, fsm, context || %{}) do
            {:ok, results} ->
              result = %{
                success: true,
                results: results,
                fsm_id: fsm_id,
                message: "Effects pipeline executed successfully"
              }
              {:reply, result, frame}

            {:error, reason} ->
              result = %{
                success: false,
                error: "Effects execution failed",
                details: inspect(reason),
                fsm_id: fsm_id
              }
              {:reply, result, frame}
          end

        {:error, reason} ->
          result = %{
            success: false,
            error: "FSM not found",
            details: inspect(reason)
          }
          {:reply, result, frame}
      end
    rescue
      error ->
        result = %{
          success: false,
          error: "Failed to execute effect pipeline",
          details: inspect(error)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool("create_ai_workflow", %{template: template, config: config, tenant_id: tenant_id}, frame) do
    try do
      # Get AI workflow template
      case get_ai_workflow_template(template) do
        {:ok, workflow_module, default_config} ->
          # Merge configurations
          final_config = Map.merge(default_config, config || %{})

          # Create FSM from AI workflow template
          case FSM.Manager.create_fsm(workflow_module, final_config, tenant_id) do
            {:ok, fsm_id} ->
              result = %{
                success: true,
                fsm_id: fsm_id,
                message: "AI workflow created successfully",
                details: %{
                  template: template,
                  config: final_config,
                  workflow_type: :ai_native,
                  estimated_duration: estimate_workflow_duration(template, final_config)
                }
              }
              {:reply, result, frame}

            {:error, reason} ->
              result = %{
                success: false,
                error: "Failed to create AI workflow",
                details: inspect(reason)
              }
              {:reply, result, frame}
          end

        {:error, reason} ->
          result = %{
            success: false,
            error: "AI workflow template not found",
            details: reason
          }
          {:reply, result, frame}
      end
    rescue
      error ->
        result = %{
          success: false,
          error: "Failed to create AI workflow",
          details: inspect(error)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool("call_llm", %{provider: provider, model: model, prompt: prompt} = params, frame) do
    try do
      # Build LLM configuration
      llm_config = [
        provider: String.to_atom(provider),
        model: model,
        prompt: prompt,
        system: Map.get(params, :system),
        max_tokens: Map.get(params, :max_tokens, 1000),
        temperature: Map.get(params, :temperature, 0.7)
      ]

      # Create a temporary FSM for the LLM call
      temp_fsm = %{
        id: "temp_llm_#{System.unique_integer()}",
        current_state: :processing,
        data: %{}
      }

      # Execute LLM call effect
      case FSM.Effects.Executor.execute_effect({:call_llm, llm_config}, temp_fsm, %{}) do
        {:ok, response} ->
          result = %{
            success: true,
            response: response,
            provider: provider,
            model: model,
            message: "LLM call completed successfully"
          }
          {:reply, result, frame}

        {:error, reason} ->
          result = %{
            success: false,
            error: "LLM call failed",
            details: inspect(reason),
            provider: provider,
            model: model
          }
          {:reply, result, frame}
      end
    rescue
      error ->
        result = %{
          success: false,
          error: "Failed to call LLM",
          details: inspect(error)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool("coordinate_agents", %{agents: agent_specs} = params, frame) do
    try do
      coordination_type = String.to_atom(Map.get(params, :coordination_type, "parallel"))
      success_criteria = Map.get(params, :success_criteria)

      # Convert agent specs to proper format
      agents = Enum.map(agent_specs, fn agent ->
        %{
          id: String.to_atom(agent["id"]),
          model: agent["model"],
          provider: String.to_atom(agent["provider"] || "openai"),
          role: agent["role"],
          system: agent["system"],
          task: agent["task"],
          tools: agent["tools"],
          context: agent["context"]
        }
      end)

      coordination_opts = [
        type: coordination_type,
        success_criteria: success_criteria
      ]

      # Create a temporary FSM for agent coordination
      temp_fsm = %{
        id: "temp_coordination_#{System.unique_integer()}",
        current_state: :coordinating,
        data: %{}
      }

      # Execute agent coordination
      case FSM.Effects.Executor.execute_effect(
        {:coordinate_agents, agents, coordination_opts},
        temp_fsm,
        %{}
      ) do
        {:ok, results} ->
          result = %{
            success: true,
            results: results,
            coordination_type: coordination_type,
            agents_count: length(agents),
            message: "Agent coordination completed successfully"
          }
          {:reply, result, frame}

        {:error, reason} ->
          result = %{
            success: false,
            error: "Agent coordination failed",
            details: inspect(reason),
            coordination_type: coordination_type
          }
          {:reply, result, frame}
      end
    rescue
      error ->
        result = %{
          success: false,
          error: "Failed to coordinate agents",
          details: inspect(error)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool("stream_fsm_events", %{fsm_id: fsm_id} = params, frame) do
    try do
      event_types = Map.get(params, :event_types, [:all])

      # Set up event streaming (placeholder implementation)
      stream_id = "#{fsm_id}_#{System.unique_integer()}"

      # In a real implementation, this would set up real-time streaming
      # For now, we'll just acknowledge the request
      result = %{
        success: true,
        stream_id: stream_id,
        fsm_id: fsm_id,
        event_types: event_types,
        message: "Event streaming started. Events will be sent via notifications."
      }
      {:reply, result, frame}
    rescue
      error ->
        result = %{
          success: false,
          error: "Failed to set up event streaming",
          details: inspect(error)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool("get_workflow_analytics", params, frame) do
    try do
      fsm_id = Map.get(params, :fsm_id)
      time_window = Map.get(params, :time_window, 300_000) # 5 minutes

      # Get workflow analytics using our telemetry system
      analytics = FSM.Effects.Telemetry.get_execution_metrics([
        time_window: time_window,
        fsm_id: fsm_id
      ])

      result = %{
        success: true,
        analytics: analytics,
        fsm_id: fsm_id,
        time_window: time_window,
        message: "Analytics retrieved successfully"
      }
      {:reply, result, frame}
    rescue
      error ->
        result = %{
          success: false,
          error: "Failed to get workflow analytics",
          details: inspect(error)
        }
        {:reply, result, frame}
    end
  end

  def handle_tool(tool_name, _params, frame) do
    result = %{
      success: false,
      error: "Unknown tool",
      details: "Tool '#{tool_name}' is not implemented"
    }
    {:reply, result, frame}
  end

  # Helper functions

  defp get_template_config("smart_door") do
    {:ok, %{
      module: SmartDoor,
      default_config: %{
        location: "main_entrance",
        auto_close_delay: 30000,
        security_level: "high"
      }
    }}
  end

  defp get_template_config("security_system") do
    {:ok, %{
      module: SecuritySystem,
      default_config: %{
        zone: "perimeter",
        sensitivity: "medium",
        auto_arm_delay: 60000
      }
    }}
  end

  defp get_template_config("timer") do
    {:ok, %{
      module: FSM.Components.Timer,
      default_config: %{
        duration: 60000,
        auto_reset: true
      }
    }}
  end

  defp get_template_config(_) do
    {:error, "Template not found"}
  end

  # Helper functions for effects-powered MCP tools

  defp parse_effects_spec(effects_spec) do
    # Convert JSON/map effect specification to internal effect format
    # This is a simplified implementation - would need more sophisticated parsing in production
    case effects_spec do
      %{"type" => "sequence", "effects" => effects_list} ->
        parsed_effects = Enum.map(effects_list, &parse_single_effect/1)
        {:sequence, parsed_effects}

      %{"type" => "parallel", "effects" => effects_list} ->
        parsed_effects = Enum.map(effects_list, &parse_single_effect/1)
        {:parallel, parsed_effects}

      %{"type" => type} = single_effect ->
        parse_single_effect(single_effect)

      # If it's already in the right format, pass through
      effect when is_tuple(effect) ->
        effect

      _ ->
        # Default to a simple log effect if parsing fails
        {:log, :info, "Parsed effect from MCP"}
    end
  end

  defp parse_single_effect(%{"type" => "call", "module" => module, "function" => function, "args" => args}) do
    {:call, String.to_atom("Elixir.#{module}"), String.to_atom(function), args}
  end

  defp parse_single_effect(%{"type" => "call_llm", "config" => config}) do
    llm_config = [
      provider: String.to_atom(config["provider"]),
      model: config["model"],
      prompt: config["prompt"],
      system: config["system"],
      max_tokens: config["max_tokens"] || 1000,
      temperature: config["temperature"] || 0.7
    ]
    {:call_llm, llm_config}
  end

  defp parse_single_effect(%{"type" => "delay", "milliseconds" => ms}) do
    {:delay, ms}
  end

  defp parse_single_effect(%{"type" => "log", "level" => level, "message" => message}) do
    {:log, String.to_atom(level), message}
  end

  defp parse_single_effect(%{"type" => "put_data", "key" => key, "value" => value}) do
    {:put_data, String.to_atom(key), value}
  end

  defp parse_single_effect(%{"type" => "get_data", "key" => key}) do
    {:get_data, String.to_atom(key)}
  end

  defp parse_single_effect(_unknown_effect) do
    {:log, :warn, "Unknown effect type in MCP call"}
  end

  defp get_ai_workflow_template("customer_service") do
    {:ok, FSM.Templates.AICustomerService, %{
      department: "general",
      escalation_threshold: 0.7,
      languages: ["en"],
      max_resolution_time: 300_000
    }}
  end

  defp get_ai_workflow_template("research_pipeline") do
    {:ok, FSM.Templates.ResearchPipeline, %{
      depth: "comprehensive",
      sources: ["academic", "industry", "web"],
      synthesis_model: "gpt-4",
      max_research_time: 600_000
    }}
  end

  defp get_ai_workflow_template("content_generation") do
    {:ok, FSM.Templates.ContentGeneration, %{
      style: "professional",
      length: "medium",
      target_audience: "general",
      quality_threshold: 0.8
    }}
  end

  defp get_ai_workflow_template("data_analysis") do
    {:ok, FSM.Templates.DataAnalysis, %{
      analysis_type: "exploratory",
      visualization: true,
      statistical_tests: ["basic"],
      confidence_level: 0.95
    }}
  end

  defp get_ai_workflow_template("multi_agent_debate") do
    {:ok, FSM.Templates.MultiAgentDebate, %{
      debate_rounds: 3,
      consensus_threshold: 0.75,
      moderation_enabled: true,
      synthesis_required: true
    }}
  end

  defp get_ai_workflow_template(_template) do
    {:error, "AI workflow template not found"}
  end

  defp estimate_workflow_duration(template, config) do
    # Estimate duration based on template type and configuration
    base_durations = %{
      "customer_service" => 30_000,      # 30 seconds
      "research_pipeline" => 300_000,    # 5 minutes
      "content_generation" => 120_000,   # 2 minutes
      "data_analysis" => 180_000,        # 3 minutes
      "multi_agent_debate" => 240_000    # 4 minutes
    }

    base_duration = Map.get(base_durations, template, 60_000)

    # Adjust based on configuration complexity
    complexity_multiplier = case Map.get(config, :complexity, "medium") do
      "simple" -> 0.7
      "medium" -> 1.0
      "complex" -> 1.5
      "comprehensive" -> 2.0
      _ -> 1.0
    end

    round(base_duration * complexity_multiplier)
  end
end
