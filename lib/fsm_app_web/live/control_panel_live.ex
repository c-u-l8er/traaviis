defmodule FSMAppWeb.ControlPanelLive do
  @moduledoc """
  Multi-tenant control panel for managing FSMs.

  Features:
  - Real-time FSM monitoring
  - FSM creation and management
  - Event sending and validation
  - Performance metrics
  - Tenant isolation
  """
  use FSMAppWeb, :live_view
  on_mount FSMAppWeb.Auth.OnMountCurrentUser
  on_mount FSMAppWeb.Auth.RequireAuthLive
  require Logger

  alias FSM.Manager
  alias FSM.Registry
  alias FSM.ModuleDiscovery
  alias FSMApp.Tenancy

  @impl true
  def mount(%{}, _session, socket) do
    # Default mount when no tenant_id is provided
    # For now, redirect to a default tenant or show tenant selection
    # You can customize this behavior based on your requirements

    # Option 1: Redirect to a default tenant (uncomment if you have a default tenant)
    # {:ok, push_redirect(socket, to: ~p"/?tenant_id=default")}

    # Option 2: Show tenant selection (current implementation)
    socket = assign(socket,
      tenant_id: nil,
      fsms: [],
      stats: %{},
      available_modules: [],
      selected_fsm: nil,
      selected_event: nil,
      selected_event_index: nil,
      events_by_fsm: %{},
      show_create_modal: false,
      show_event_modal: false,
      selected_module: nil,
      fsm_config: %{},
      event_name: "",
      event_data: %{},
      available_events: [],
      tenants: assigned_tenants(socket),
      subscribed_tenant_id: nil,
      page_title: "Dashboard" # FSM Control Panel - Select Tenant
    )

    {:ok, socket}
  end

  @impl true
  def mount(%{"tenant_id" => tenant_id}, _session, socket) do
    if connected?(socket) do
      # Join the FSM channel for real-time updates (avoid duplicate subscriptions)
      if socket.assigns[:subscribed_tenant_id] != tenant_id do
        Phoenix.PubSub.subscribe(FSMApp.PubSub, "fsm:#{tenant_id}")
      end

      # Set up periodic updates
      :timer.send_interval(5000, self(), :update_stats)
    end

    # Load initial data
    _ = FSM.Registry.reload_from_disk()
    {:ok, fsms} = Manager.get_tenant_fsms(tenant_id)
    stats = get_tenant_stats(tenant_id)
    available_modules = get_available_modules()
    events_by_fsm = preload_events_for_fsms(fsms)

    socket = assign(socket,
      tenant_id: tenant_id,
      fsms: fsms,
      stats: stats,
      available_modules: available_modules,
      selected_fsm: nil,
      selected_event: nil,
      selected_event_index: nil,
      events_by_fsm: events_by_fsm,
      show_create_modal: false,
      show_event_modal: false,
      selected_module: nil,
      fsm_config: %{},
      event_name: "",
      event_data: %{},
      available_events: [],
      tenants: assigned_tenants(socket),
      subscribed_tenant_id: tenant_id,
      page_title: "#{tenant_id}"
    )

    {:ok, socket}
  end

  @impl true
  def handle_event("show_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: true)}
  end

  def handle_event("hide_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: false, selected_module: nil, fsm_config: %{})}
  end

  def handle_event("select_module", %{"module" => module_name}, socket) do
    # Update the selected module for display purposes
    module = Enum.find(socket.assigns.available_modules, fn m -> m.name == module_name end)
    {:noreply, assign(socket, selected_module: module)}
  end

  def handle_event("update_config", %{"config" => config}, socket) do
    {:noreply, assign(socket, fsm_config: config)}
  end

  def handle_event("update_event_name", %{"event_name" => event_name}, socket) do
    {:noreply, assign(socket, event_name: event_name)}
  end

  def handle_event("select_tenant", %{"tenant_id" => tenant_id}, socket) do
    # Update the tenant_id and reload data for the new tenant
    if connected?(socket) and socket.assigns.subscribed_tenant_id != tenant_id do
      # Switch PubSub topic: unsubscribe old, subscribe new
      old = socket.assigns.subscribed_tenant_id
      if old && old != tenant_id do
        Phoenix.PubSub.unsubscribe(FSMApp.PubSub, "fsm:#{old}")
      end
      Phoenix.PubSub.subscribe(FSMApp.PubSub, "fsm:#{tenant_id}")
      # Note: Timer is already set up in mount, no need to set it up again
    end

    # Load initial data for the new tenant
    _ = FSM.Registry.reload_from_disk()
    {:ok, fsms} = Manager.get_tenant_fsms(tenant_id)
    stats = get_tenant_stats(tenant_id)
    available_modules = get_available_modules()
    events_by_fsm = preload_events_for_fsms(fsms)

    socket = assign(socket,
      tenant_id: tenant_id,
      fsms: fsms,
      stats: stats,
      available_modules: available_modules,
      selected_fsm: nil,
      selected_event: nil,
      selected_event_index: nil,
      events_by_fsm: events_by_fsm,
      show_create_modal: false,
      show_event_modal: false,
      selected_module: nil,
      fsm_config: %{},
      event_name: "",
      event_data: %{},
      tenants: assigned_tenants(socket),
      subscribed_tenant_id: tenant_id,
      page_title: "#{tenant_id}"
    )

    {:noreply, socket}
  end

  def handle_event("create_fsm", _params, %{assigns: %{tenant_id: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Please select a tenant first")}
  end

  def handle_event("create_fsm", %{"module" => module_name, "config" => config_json}, socket) do
    case module_name do
      "" ->
        {:noreply, put_flash(socket, :error, "Please select a module first")}

      _ ->
        # Parse the config JSON
        config = case Jason.decode(config_json) do
          {:ok, parsed_config} -> parsed_config
          {:error, _} -> %{}
        end

        # Actually create the FSM using the factory
        case FSM.Factory.create_fsm(module_name, config, socket.assigns.tenant_id) do
          {:ok, _fsm} ->
            # Refresh the FSM list
            {:ok, fsms} = Manager.get_tenant_fsms(socket.assigns.tenant_id)
            stats = get_tenant_stats(socket.assigns.tenant_id)

            {:noreply,
              socket
              |> assign(fsms: fsms, stats: stats, show_create_modal: false, selected_module: nil, fsm_config: %{})
              |> put_flash(:info, "FSM created successfully")}

          {:error, reason} ->
            {:noreply,
              socket
              |> put_flash(:error, "Failed to create FSM: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("create_fsm", _params, socket) do
    {:noreply, put_flash(socket, :error, "Invalid form data")}
  end

  def handle_event("show_event_modal", %{"fsm_id" => _fsm_id}, %{assigns: %{tenant_id: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Please select a tenant first")}
  end

  def handle_event("show_event_modal", %{"fsm_id" => fsm_id}, socket) do
    fsm = Enum.find(socket.assigns.fsms, fn f -> f.id == fsm_id end)

    # Get available events for this FSM
    available_events = get_available_events(fsm_id)

    {:noreply, assign(socket,
      show_event_modal: true,
      selected_fsm: fsm,
      available_events: available_events
    )}
  end

  def handle_event("select_fsm", %{"fsm_id" => fsm_id}, socket) do
    fsm = Enum.find(socket.assigns.fsms, fn f -> f.id == fsm_id end)
    
    # Debug: Log the selected FSM and available events
    events = Map.get(socket.assigns.events_by_fsm, fsm_id, [])
    Logger.info("Selected FSM: #{inspect(fsm_id)}, Events count: #{length(events)}")
    Logger.info("Events by FSM keys: #{inspect(Map.keys(socket.assigns.events_by_fsm))}")
    Logger.info("FSM object ID from struct: #{inspect(fsm && fsm.id)}")
    
    # Refresh events for this specific FSM
    updated_events_by_fsm = if fsm do
      case FSM.EventStore.list(fsm.id) do
        {:ok, fresh_events} ->
          entries =
            fresh_events
            |> Enum.map(fn ev ->
              case ev do
                %{"type" => "transition"} = t ->
                  %{
                    event: t["event"],
                    from: t["from"],
                    to: t["to"],
                    data: t["event_data"],
                    timestamp: parse_event_timestamp(t["timestamp"])
                  }
                %{"type" => "created"} = c ->
                  %{
                    event: "created",
                    from: nil,
                    to: c["initial_state"],
                    data: c["initial_data"],
                    timestamp: parse_event_timestamp(c["timestamp"])
                  }
                _ -> nil
              end
            end)
            |> Enum.filter(& &1)
          
          Logger.info("Fresh events for FSM #{inspect(fsm.id)}: #{length(entries)}")
          Map.put(socket.assigns.events_by_fsm, fsm.id, entries)
        {:error, _reason} ->
          Logger.warn("Failed to load events for FSM #{inspect(fsm.id)}")
          socket.assigns.events_by_fsm
      end
    else
      socket.assigns.events_by_fsm
    end
    
    {:noreply,
      assign(socket,
        selected_fsm: fsm,
        selected_event: nil,
        selected_event_index: nil,
        events_by_fsm: updated_events_by_fsm
      )}
  end

  def handle_event("select_event", %{"index" => index_str}, socket) do
    with %{} = fsm <- socket.assigns.selected_fsm do
      events = Map.get(socket.assigns.events_by_fsm, fsm.id, [])
      index = String.to_integer(index_str)
      event = Enum.at(events, index)
      {:noreply, assign(socket, selected_event: event, selected_event_index: index)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("hide_event_modal", _params, socket) do
    {:noreply, assign(socket, show_event_modal: false, selected_fsm: nil, event_name: "", event_data: %{})}
  end

  def handle_event("update_event_data", %{"event_data" => event_data}, socket) do
    {:noreply, assign(socket, event_data: event_data)}
  end

  def handle_event("send_event", _params, %{assigns: %{tenant_id: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Please select a tenant first")}
  end

  def handle_event("send_event", params, socket) do
    case socket.assigns.selected_fsm do
      nil ->
        {:noreply, put_flash(socket, :error, "No FSM selected")}

      fsm ->
        event_name = Map.get(params, "event_name", socket.assigns.event_name)
        event_data_json = Map.get(params, "event_data", nil)
        event_data =
          case event_data_json do
            nil -> socket.assigns.event_data
            "" -> %{}
            data -> case Jason.decode(data) do
              {:ok, decoded} -> decoded
              _ -> socket.assigns.event_data
            end
          end

        if event_name == "" do
          {:noreply, put_flash(socket, :error, "Event name is required")}
        else
          # Actually send the event to the FSM
          case send_event_to_fsm(fsm.id, event_name, event_data) do
            {:ok, _updated_fsm} ->
              # Refresh the FSM list to show the updated state
              {:ok, fsms} = Manager.get_tenant_fsms(socket.assigns.tenant_id)
              stats = get_tenant_stats(socket.assigns.tenant_id)

            {:noreply,
              socket
              |> assign(
                fsms: fsms,
                stats: stats,
                show_event_modal: false,
                selected_fsm: Enum.find(fsms, fn f -> f.id == fsm.id end),
                selected_event: nil,
                selected_event_index: nil,
                event_name: "",
                event_data: %{}
              )
              |> put_flash(:info, "Event '#{event_name}' processed successfully")}

            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Failed to process event: #{inspect(reason)}")}
          end
        end
    end
  end

  def handle_event("destroy_fsm", %{"fsm_id" => _fsm_id}, %{assigns: %{tenant_id: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Please select a tenant first")}
  end

  def handle_event("destroy_fsm", %{"fsm_id" => fsm_id}, socket) do
    # Actually destroy the FSM using the factory
    case FSM.Factory.destroy_fsm(fsm_id) do
      {:ok, _} ->
        # Refresh the FSM list
        {:ok, fsms} = Manager.get_tenant_fsms(socket.assigns.tenant_id)
        stats = get_tenant_stats(socket.assigns.tenant_id)

        {:noreply,
          socket
          |> assign(fsms: fsms, stats: stats)
          |> put_flash(:info, "FSM destroyed successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to destroy FSM: #{inspect(reason)}")}
    end
  end

  def handle_event("refresh", _params, %{assigns: %{tenant_id: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Please select a tenant first")}
  end

  def handle_event("refresh", _params, socket) do
    # Refresh FSM list
    _ = FSM.Registry.reload_from_disk()
    {:ok, fsms} = Manager.get_tenant_fsms(socket.assigns.tenant_id)
    stats = get_tenant_stats(socket.assigns.tenant_id)
    events_by_fsm = preload_events_for_fsms(fsms)

    {:noreply,
      socket
      |> assign(fsms: fsms, stats: stats, events_by_fsm: events_by_fsm)
      |> put_flash(:info, "Data refreshed")}
  end

  def handle_event("validate_transition", %{"fsm_id" => _fsm_id, "event" => _event}, socket) do
    # This would typically call the validation endpoint
    # For now, we'll just show a message
    {:noreply, put_flash(socket, :info, "Transition validation would be performed here")}
  end

  @impl true
  def handle_info(%{event: "fsm_created", payload: payload}, socket) do
    # Add new FSM to the list
    new_fsm = %{
      id: payload.fsm_id,
      module: payload.module,
      current_state: "initial", # This would come from the actual FSM
      tenant_id: payload.tenant_id,
      metadata: %{
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        version: 1,
        tags: []
      }
    }

    # Ensure we don't add duplicates if the event is received multiple times
    updated_fsms = [new_fsm | Enum.reject(socket.assigns.fsms, fn f -> f.id == payload.fsm_id end)]

    {:noreply,
      socket
      |> assign(fsms: updated_fsms)
      |> put_flash(:info, "New FSM created: #{payload.fsm_id}")}
  end

  def handle_info(%{event: "fsm_destroyed", payload: payload}, socket) do
    # Remove FSM from the list
    updated_fsms = Enum.reject(socket.assigns.fsms, fn f -> f.id == payload.fsm_id end)

    {:noreply,
      socket
      |> assign(fsms: updated_fsms)
      |> put_flash(:info, "FSM destroyed: #{payload.fsm_id}")}
  end

  def handle_info(%{event: "fsm_state_changed", payload: payload}, socket) do
    # Update FSM state in the list
    updated_fsms = Enum.map(socket.assigns.fsms, fn fsm ->
      if fsm.id == payload.fsm_id do
        fsm
        |> Map.put(:current_state, payload.to)
        |> Map.put(:data, payload.data)
      else
        fsm
      end
    end)

    # Append event entry to the per-FSM events log
    timestamp = Map.get(payload, :timestamp, DateTime.utc_now())
    event_name = Map.get(payload, :event)
    event_entry = %{
      event: event_name,
      from: payload.from,
      to: payload.to,
      data: payload.data,
      timestamp: timestamp
    }

    events_by_fsm = Map.update(socket.assigns.events_by_fsm, payload.fsm_id, [event_entry], fn list ->
      case List.last(list) do
        ^event_entry -> list
        _ -> list ++ [event_entry]
      end
    end)

    {:noreply,
      socket
      |> assign(fsms: updated_fsms, events_by_fsm: events_by_fsm)
      |> put_flash(:info, "FSM #{payload.fsm_id} state changed to #{payload.to}")}
  end

  def handle_info(:update_stats, %{assigns: %{tenant_id: nil}} = socket) do
    # No tenant selected, skip stats update
    {:noreply, socket}
  end

  # Handle timers from components (e.g., auto-close)
  def handle_info({:timer_expired, :auto_close, %{fsm_id: fsm_id}}, socket) do
    # Mark this transition as auto_close-driven so the FSM can start a safety timer
    _ = send_event_to_fsm(fsm_id, "auto_close", %{auto_close: true})
    {:noreply, socket}
  end

  # Ignore other timer messages
  def handle_info({:timer_expired, :fully_closed, %{fsm_id: fsm_id}}, socket) do
    _ = send_event_to_fsm(fsm_id, "fully_closed", %{})
    {:noreply, socket}
  end

  def handle_info({:timer_expired, _name}, socket), do: {:noreply, socket}
  def handle_info({:timer_expired, _name, _payload}, socket), do: {:noreply, socket}

  def handle_info(:update_stats, socket) do
    stats = get_tenant_stats(socket.assigns.tenant_id)
    {:noreply, assign(socket, stats: stats)}
  end

  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  # Private functions
  defp preload_events_for_fsms(fsms) do
    Enum.reduce(fsms, %{}, fn fsm, acc ->
      {:ok, events} = FSM.EventStore.list(fsm.id)
      entries =
        events
        |> Enum.map(fn ev ->
          case ev do
            %{"type" => "transition"} = t ->
              %{
                event: t["event"],
                from: t["from"],
                to: t["to"],
                data: t["event_data"],
                timestamp: parse_event_timestamp(t["timestamp"])
              }
            %{"type" => "created"} = c ->
              %{
                event: "created",
                from: nil,
                to: c["initial_state"],
                data: c["initial_data"],
                timestamp: parse_event_timestamp(c["timestamp"])
              }
            _ -> nil
          end
        end)
        |> Enum.filter(& &1)
      Logger.info("Preloaded events for FSM #{inspect(fsm.id)}: #{length(entries)} events")
      Map.put(acc, fsm.id, entries)
    end)
  end

  defp parse_event_timestamp(%DateTime{} = dt), do: dt
  defp parse_event_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
  defp parse_event_timestamp(_), do: DateTime.utc_now()
  defp assigned_tenants(%{assigns: %{current_user: nil}}), do: []
  defp assigned_tenants(%{assigns: %{current_user: current_user}}) do
    Tenancy.list_user_tenants(current_user.id)
  end

  defp send_event_to_fsm(fsm_id, event_name, event_data) do
    require Logger

    Logger.info("Sending event '#{event_name}' to FSM #{fsm_id} with data: #{inspect(event_data)}")

    # Get the FSM from the registry
    case FSM.Registry.get(fsm_id) do
      {:ok, {module, fsm}} ->
        Logger.info("Found FSM #{fsm_id} with module #{module}, current state: #{fsm.current_state}")

        # Convert event_name string to atom for the FSM
        event_atom = String.to_existing_atom(event_name)
        Logger.info("Converted event name '#{event_name}' to atom: #{event_atom}")

        # Send the event to the FSM
        Logger.info("Calling #{module}.navigate(#{inspect(fsm)}, #{event_atom}, #{inspect(event_data)})")

        case module.navigate(fsm, event_atom, event_data) do
          {:ok, updated_fsm} ->
            Logger.info("FSM navigation successful. State changed from #{fsm.current_state} to #{updated_fsm.current_state}")

            # Update the FSM in the registry
            FSM.Registry.update(fsm_id, updated_fsm)
            Logger.info("FSM updated in registry")

            # Broadcast state change for real-time updates
            Phoenix.PubSub.broadcast!(FSMApp.PubSub, "fsm:#{fsm.tenant_id}", %{
              event: "fsm_state_changed",
              payload: %{
                fsm_id: fsm_id,
                event: event_name,
                from: fsm.current_state,
                to: updated_fsm.current_state,
                data: updated_fsm.data,
                timestamp: DateTime.utc_now()
              }
            })

            {:ok, updated_fsm}

          {:error, reason} ->
            Logger.error("FSM navigation failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, :not_found} ->
        Logger.error("FSM #{fsm_id} not found in registry")
        {:error, :fsm_not_found}
    end
  rescue
    ArgumentError ->
      Logger.error("Invalid event name: #{event_name}")
      {:error, :invalid_event_name}
    e ->
      Logger.error("Unexpected error in send_event_to_fsm: #{inspect(e)}")
      {:error, {:unexpected_error, e}}
  end

  defp get_available_events(fsm_id) do
    case FSM.Registry.get(fsm_id) do
      {:ok, {module, fsm}} ->
        # Get available events for the current state
        possible_destinations = module.possible_destinations(fsm)

        # Extract just the event names
        possible_destinations
        |> Enum.map(fn {event, _to, _opts} -> event end)
        |> Enum.uniq()

      {:error, :not_found} ->
        []
    end
  end

  defp get_tenant_stats(nil) do
    %{fsm_count: 0, error: "No tenant selected"}
  end

  defp get_tenant_stats(tenant_id) do
    try do
      manager_stats = Manager.get_stats()
      registry_stats = Registry.stats()

      # Filter stats for the specific tenant
      tenant_fsms = Registry.list_by_tenant(tenant_id)

      %{
        fsm_count: length(tenant_fsms),
        manager_stats: manager_stats,
        registry_stats: registry_stats,
        timestamp: DateTime.utc_now()
      }
    rescue
      _ -> %{fsm_count: 0, error: "Failed to load stats"}
    end
  end

  defp get_available_modules do
    # Discover modules dynamically and enrich with optional state/component hints if available
    ModuleDiscovery.list_available_fsms()
    |> Enum.map(fn m ->
      Map.merge(%{states: [], components: []}, m)
    end)
  end

  defp format_timestamp(nil), do: "N/A"
  defp format_timestamp(timestamp) do
    Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S")
  end

  defp encode_pretty_json(value) do
    try do
      Jason.encode!(value, pretty: true)
    rescue
      _ -> inspect(value)
    end
  end

  defp get_state_color("closed"), do: "bg-gray-500"
  defp get_state_color("opening"), do: "bg-yellow-500"
  defp get_state_color("open"), do: "bg-green-500"
  defp get_state_color("closing"), do: "bg-orange-500"
  defp get_state_color("monitoring"), do: "bg-blue-500"
  defp get_state_color("disarmed"), do: "bg-red-500"
  defp get_state_color("alarm"), do: "bg-red-600"
  defp get_state_color("idle"), do: "bg-gray-400"
  defp get_state_color("running"), do: "bg-green-400"
  defp get_state_color("paused"), do: "bg-yellow-400"
  defp get_state_color("expired"), do: "bg-red-400"
  defp get_state_color(_), do: "bg-gray-300"
end
