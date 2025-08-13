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
    }
  end

  def handle_tool("create_fsm", %{module: module_name, config: config, tenant_id: tenant_id}, frame) do
    try do
      # Convert module name string to actual module
      module = String.to_existing_atom(module_name)

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
    available_modules = [
      %{name: "FSM.SmartDoor", description: "Smart door with security and timer components"},
      %{name: "FSM.SecuritySystem", description: "Security system with monitoring and alarm states"},
      %{name: "FSM.Timer", description: "Basic timer with idle, running, paused, and expired states"},
      %{name: "FSM.Orchestrators.Saga", description: "Saga orchestrator for multi-step workflows with compensation"},
      %{name: "FSM.Orchestrators.PlanExecute", description: "Deterministic plan-execute-observe-evaluate loop"},
      %{name: "FSM.Orchestrators.TaskRouter", description: "Task routing based on policy and retrieval"},
      %{name: "FSM.Safety.ApprovalGate", description: "Human-in-the-loop approval with escalation"},
      %{name: "FSM.Safety.BudgetGuard", description: "Budget and quota enforcement"},
      %{name: "FSM.Reliability.CircuitBreaker", description: "Circuit breaker for reliability"},
      %{name: "FSM.Integration.ApiCall", description: "External API call with OAuth refresh"}
    ]

    result = %{
      success: true,
      available_modules: available_modules
    }
    {:reply, result, frame}
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
end
