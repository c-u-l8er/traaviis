defmodule FSMAppWeb.FSMChannel do
  @moduledoc """
  WebSocket channel for real-time FSM communication.

  This channel provides:
  - Real-time FSM state updates
  - Event broadcasting
  - Tenant isolation
  - Authentication and authorization
  """
  use FSMAppWeb, :channel
  require Logger

  alias FSM.Manager
  alias FSM.Registry

  @impl true
  def join("fsm:" <> tenant_id, _params, socket) do
    # Verify tenant access
    if authorized?(socket, tenant_id) do
      # Join the tenant-specific topic
      {:ok, assign(socket, :tenant_id, tenant_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("create_fsm", %{"module" => module_name, "config" => config}, socket) do
    tenant_id = socket.assigns.tenant_id

    try do
      module = String.to_existing_atom(module_name)

      case Manager.create_fsm(module, config, tenant_id) do
        {:ok, fsm_id} ->
          # Broadcast FSM creation to all clients in the tenant
          broadcast!(socket, "fsm_created", %{
            fsm_id: fsm_id,
            module: module_name,
            tenant_id: tenant_id,
            config: config
          })

          # Send confirmation to the client
          {:reply, {:ok, %{fsm_id: fsm_id}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: inspect(reason)}}, socket}
      end

    rescue
      ArgumentError ->
        {:reply, {:error, %{reason: "Invalid module name"}}, socket}
      e ->
        Logger.error("Error creating FSM: #{inspect(e)}")
        {:reply, {:error, %{reason: "Internal error"}}, socket}
    end
  end

  def handle_in("send_event", %{"fsm_id" => fsm_id, "event" => event, "event_data" => event_data}, socket) do
    _tenant_id = socket.assigns.tenant_id

    try do
      case Manager.send_event(fsm_id, String.to_atom(event), event_data || %{}) do
        {:ok, fsm} ->
          # Broadcast state change to all clients in the tenant
          broadcast!(socket, "fsm_state_changed", %{
            fsm_id: fsm_id,
            event: event,
            from: fsm.current_state, # This should be the previous state
            to: fsm.current_state,
            data: fsm.data,
            timestamp: DateTime.utc_now()
          })

          {:reply, {:ok, %{new_state: fsm.current_state, data: fsm.data}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: inspect(reason)}}, socket}
      end

    rescue
      e ->
        Logger.error("Error sending event: #{inspect(e)}")
        {:reply, {:error, %{reason: "Internal error"}}, socket}
    end
  end

  def handle_in("get_fsm_state", %{"fsm_id" => fsm_id}, socket) do
    case Manager.get_fsm_state(fsm_id) do
      {:ok, state_info} ->
        {:reply, {:ok, state_info}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("list_fsms", _params, socket) do
    tenant_id = socket.assigns.tenant_id

    case Manager.get_tenant_fsms(tenant_id) do
      {:ok, fsms} ->
        {:reply, {:ok, %{fsms: fsms, count: length(fsms)}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("destroy_fsm", %{"fsm_id" => fsm_id}, socket) do
    case Manager.destroy_fsm(fsm_id) do
      :ok ->
        # Broadcast FSM destruction to all clients in the tenant
        broadcast!(socket, "fsm_destroyed", %{
          fsm_id: fsm_id,
          timestamp: DateTime.utc_now()
        })

        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("subscribe_to_fsm", %{"fsm_id" => fsm_id}, socket) do
    # Add FSM to the socket's subscribed FSMs
    subscribed_fsms = MapSet.new(socket.assigns[:subscribed_fsms] || [])
    updated_fsms = MapSet.put(subscribed_fsms, fsm_id)

    socket = assign(socket, :subscribed_fsms, updated_fsms)

    # Send confirmation
    {:reply, {:ok, %{subscribed: true, fsm_id: fsm_id}}, socket}
  end

  def handle_in("unsubscribe_from_fsm", %{"fsm_id" => fsm_id}, socket) do
    # Remove FSM from the socket's subscribed FSMs
    subscribed_fsms = MapSet.new(socket.assigns[:subscribed_fsms] || [])
    updated_fsms = MapSet.delete(subscribed_fsms, fsm_id)

    socket = assign(socket, :subscribed_fsms, updated_fsms)

    # Send confirmation
    {:reply, {:ok, %{unsubscribed: true, fsm_id: fsm_id}}, socket}
  end

  def handle_in("get_fsm_metrics", %{"fsm_id" => fsm_id}, socket) do
    case Manager.get_fsm_metrics(fsm_id) do
      {:ok, metrics} ->
        {:reply, {:ok, metrics}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("batch_send_events", %{"events" => events}, socket) do
    _tenant_id = socket.assigns.tenant_id

    try do
      # Format events for the manager
      formatted_events = Enum.map(events, fn event ->
        {
          event["fsm_id"],
          String.to_atom(event["event"]),
          event["event_data"] || %{}
        }
      end)

      case Manager.batch_send_events(formatted_events) do
        {:ok, results} ->
          # Broadcast results to all clients in the tenant
          broadcast!(socket, "batch_events_processed", %{
            total_events: length(events),
            results: results,
            timestamp: DateTime.utc_now()
          })

          {:reply, {:ok, %{results: results, total: length(events)}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: inspect(reason)}}, socket}
      end

    rescue
      e ->
        Logger.error("Error in batch events: #{inspect(e)}")
        {:reply, {:error, %{reason: "Internal error"}}, socket}
    end
  end

  def handle_in("ping", _params, socket) do
    {:reply, {:ok, %{pong: true, timestamp: DateTime.utc_now()}}, socket}
  end

  def handle_in("get_tenant_stats", _params, socket) do
    tenant_id = socket.assigns.tenant_id

    try do
      manager_stats = Manager.get_stats()
      registry_stats = Registry.stats()

      # Filter stats for the specific tenant
      tenant_fsms = Registry.list_by_tenant(tenant_id)

      tenant_stats = %{
        fsm_count: length(tenant_fsms),
        manager_stats: manager_stats,
        registry_stats: registry_stats,
        timestamp: DateTime.utc_now()
      }

      {:reply, {:ok, tenant_stats}, socket}

    rescue
      e ->
        Logger.error("Error getting tenant stats: #{inspect(e)}")
        {:reply, {:error, %{reason: "Internal error"}}, socket}
    end
  end

  def handle_in("validate_transition", %{"fsm_id" => fsm_id, "event" => event, "event_data" => _event_data}, socket) do
    try do
      case Registry.get(fsm_id) do
        {:ok, {module, fsm}} ->
          can_navigate = module.can_navigate?(fsm, String.to_atom(event))
          possible_destinations = module.possible_destinations(fsm)

          result = %{
            can_transition: can_navigate,
            current_state: fsm.current_state,
            event: event,
            possible_destinations: possible_destinations
          }

          {:reply, {:ok, result}, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: inspect(reason)}}, socket}
      end

    rescue
      e ->
        Logger.error("Error validating transition: #{inspect(e)}")
        {:reply, {:error, %{reason: "Internal error"}}, socket}
    end
  end

  def handle_in("get_available_modules", _params, socket) do
    # Return available FSM modules
    available_modules = [
      %{
        name: "SmartDoor",
        description: "Smart door with security and timer components",
        states: ["closed", "opening", "open", "closing"],
        components: ["Timer", "Security"]
      },
      %{
        name: "SecuritySystem",
        description: "Security system with monitoring and alarm states",
        states: ["monitoring", "disarmed", "alarm"],
        components: ["Security"]
      },
      %{
        name: "Timer",
        description: "Basic timer with idle, running, paused, and expired states",
        states: ["idle", "running", "paused", "expired"],
        components: []
      }
    ]

    {:reply, {:ok, %{modules: available_modules}}, socket}
  end

  def handle_in("create_from_template", %{"template" => template_name, "config" => config}, socket) do
    tenant_id = socket.assigns.tenant_id

    try do
      case get_template_config(template_name) do
        {:ok, template_config} ->
          # Merge template config with user config
          final_config = Map.merge(template_config.default_config, config || %{})

          # Create FSM using the template
          case Manager.create_fsm(template_config.module, final_config, tenant_id) do
            {:ok, fsm_id} ->
              # Broadcast FSM creation
              broadcast!(socket, "fsm_created_from_template", %{
                fsm_id: fsm_id,
                template: template_name,
                config: final_config,
                tenant_id: tenant_id
              })

              {:reply, {:ok, %{fsm_id: fsm_id, template: template_name}}, socket}

            {:error, reason} ->
              {:reply, {:error, %{reason: inspect(reason)}}, socket}
          end

        {:error, reason} ->
          {:reply, {:error, %{reason: reason}}, socket}
      end

    rescue
      e ->
        Logger.error("Error creating from template: #{inspect(e)}")
        {:reply, {:error, %{reason: "Internal error"}}, socket}
    end
  end

  def handle_in("unknown", _params, socket) do
    {:reply, {:error, %{reason: "Unknown command"}}, socket}
  end

  @impl true
  def handle_info({:fsm_state_changed, fsm_id, event, from, to, data}, socket) do
    # Check if this socket is subscribed to this FSM
    subscribed_fsms = socket.assigns[:subscribed_fsms] || MapSet.new()

    if MapSet.member?(subscribed_fsms, fsm_id) do
      push(socket, "fsm_state_changed", %{
        fsm_id: fsm_id,
        event: event,
        from: from,
        to: to,
        data: data,
        timestamp: DateTime.utc_now()
      })
    end

    {:noreply, socket}
  end

  @impl true
  def terminate(reason, _socket) do
    Logger.info("FSM Channel terminated: #{inspect(reason)}")
    :ok
  end

  # Private functions

  defp authorized?(_socket, _tenant_id) do
    # In a real application, you would verify the user's access to the tenant
    # For now, we'll just check if the user is authenticated
    # Simplified for now - always return true
    true
  end

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
