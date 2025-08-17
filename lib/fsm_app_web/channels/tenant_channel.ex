defmodule FSMAppWeb.TenantChannel do
  @moduledoc """
  Secure tenant-isolated WebSocket channels.

  Provides real-time communication within tenant boundaries with:
  - JWT-based authentication
  - Tenant context validation
  - Permission-based message handling
  - Real-time workflow and effects monitoring
  - Collaborative editing support
  """

  use FSMAppWeb, :channel
  alias FSMAppWeb.Auth.{Pipeline, ErrorHandler}
  alias FSMApp.{Authorization, Accounts}
  alias FSMApp.Storage.HybridStore
  require Logger

  @doc """
  Join tenant channel with authentication and authorization.
  """
  def join("tenant:" <> tenant_id, params, socket) do
    Logger.debug("Attempting to join tenant channel: #{tenant_id}")

    with {:ok, authenticated_socket} <- authenticate_socket(socket, params),
         {:ok, authorized_socket} <- authorize_tenant_access(authenticated_socket, tenant_id),
         :ok <- validate_tenant_permissions(authorized_socket, tenant_id) do

      # Subscribe to tenant-specific PubSub topics
      Phoenix.PubSub.subscribe(FSMApp.PubSub, "tenant:#{tenant_id}")
      Phoenix.PubSub.subscribe(FSMApp.PubSub, "tenant:#{tenant_id}:workflows")
      Phoenix.PubSub.subscribe(FSMApp.PubSub, "tenant:#{tenant_id}:effects")

      # Track presence
      {:ok, _} = FSMAppWeb.Presence.track(authorized_socket, tenant_id, %{
        user: authorized_socket.assigns.current_user,
        joined_at: DateTime.utc_now(),
        permissions: authorized_socket.assigns.tenant_permissions
      })

      # Send initial state
      initial_state = get_initial_tenant_state(tenant_id, authorized_socket.assigns.current_user)

      Logger.info("User #{authorized_socket.assigns.current_user.id} joined tenant #{tenant_id}")

      {:ok, initial_state, authorized_socket}
    else
      {:error, reason} ->
        Logger.warning("Failed to join tenant #{tenant_id}: #{inspect(reason)}")
        error_response = ErrorHandler.handle_socket_auth_error(:forbidden, reason)
        {:error, error_response}
    end
  end

  def handle_in("workflow:create", payload, socket) do
    if has_permission?(socket, :workflow_create) do
      case create_tenant_workflow(socket.assigns.tenant_id, payload, socket.assigns.current_user) do
        {:ok, workflow} ->
          # Broadcast to all tenant members
          broadcast!(socket, "workflow:created", %{
            workflow: workflow,
            created_by: socket.assigns.current_user.id,
            timestamp: DateTime.utc_now()
          })

          {:reply, {:ok, %{workflow_id: workflow.id}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: reason}}, socket}
      end
    else
      {:reply, {:error, %{reason: "insufficient_permissions"}}, socket}
    end
  end

  def handle_in("workflow:execute", %{"workflow_id" => workflow_id, "event" => event} = payload, socket) do
    if has_permission?(socket, :workflow_execute) do
      tenant_id = socket.assigns.tenant_id
      event_data = Map.get(payload, "event_data", %{})

      case execute_tenant_workflow(tenant_id, workflow_id, event, event_data) do
        {:ok, result} ->
          # Broadcast execution update
          broadcast!(socket, "workflow:executed", %{
            workflow_id: workflow_id,
            event: event,
            result: result,
            executed_by: socket.assigns.current_user.id,
            timestamp: DateTime.utc_now()
          })

          {:reply, {:ok, result}, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: reason}}, socket}
      end
    else
      {:reply, {:error, %{reason: "insufficient_permissions"}}, socket}
    end
  end

  def handle_in("effects:execute", payload, socket) do
    if has_permission?(socket, :effects_execute) do
      case execute_tenant_effects(socket.assigns.tenant_id, payload, socket.assigns.current_user) do
        {:ok, execution_id} ->
          # Start streaming execution progress
          stream_effects_execution(socket, execution_id)

          {:reply, {:ok, %{execution_id: execution_id}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: reason}}, socket}
      end
    else
      {:reply, {:error, %{reason: "insufficient_permissions"}}, socket}
    end
  end

  def handle_in("collaboration:update", %{"resource_type" => resource_type, "resource_id" => resource_id} = payload, socket) do
    if has_permission?(socket, collaboration_permission(resource_type)) do
      operation = Map.get(payload, "operation", %{})

      case apply_collaborative_operation(socket.assigns.tenant_id, resource_type, resource_id, operation, socket.assigns.current_user) do
        {:ok, updated_state} ->
          # Broadcast to all collaborators except sender
          broadcast_from!(socket, "collaboration:updated", %{
            resource_type: resource_type,
            resource_id: resource_id,
            operation: operation,
            state: updated_state,
            user: socket.assigns.current_user,
            timestamp: DateTime.utc_now()
          })

          {:noreply, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: reason}}, socket}
      end
    else
      {:reply, {:error, %{reason: "insufficient_permissions"}}, socket}
    end
  end

  def handle_in("monitoring:subscribe", %{"resource_types" => resource_types}, socket) do
    if has_permission?(socket, :system_metrics_view) do
      # Subscribe to monitoring streams
      Enum.each(resource_types, fn resource_type ->
        Phoenix.PubSub.subscribe(FSMApp.PubSub, "monitoring:#{socket.assigns.tenant_id}:#{resource_type}")
      end)

      {:reply, {:ok, %{subscribed_to: resource_types}}, socket}
    else
      {:reply, {:error, %{reason: "insufficient_permissions"}}, socket}
    end
  end

  def handle_in("tenant:update_config", payload, socket) do
    if has_permission?(socket, :tenant_settings) do
      case update_tenant_config(socket.assigns.tenant_id, payload, socket.assigns.current_user) do
        {:ok, updated_config} ->
          # Broadcast config update to all tenant members
          broadcast!(socket, "tenant:config_updated", %{
            config: updated_config,
            updated_by: socket.assigns.current_user.id,
            timestamp: DateTime.utc_now()
          })

          {:reply, {:ok, updated_config}, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: reason}}, socket}
      end
    else
      {:reply, {:error, %{reason: "insufficient_permissions"}}, socket}
    end
  end

  @doc """
  Handle presence updates and user activity.
  """
  def handle_in("presence:update", payload, socket) do
    # Update user presence information
    {:ok, _} = FSMAppWeb.Presence.update(socket, socket.assigns.tenant_id, fn meta ->
      Map.merge(meta, payload)
    end)

    {:noreply, socket}
  end

  # PubSub message handlers

  def handle_info(%{topic: "tenant:" <> _topic, event: event, payload: payload}, socket) do
    # Forward tenant-level events to the client
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_info(%{topic: "monitoring:" <> _topic, event: event, payload: payload}, socket) do
    # Forward monitoring events to subscribed clients
    push(socket, event, payload)
    {:noreply, socket}
  end

  # Private helper functions

  defp authenticate_socket(socket, params) do
    case Pipeline.authenticate_socket(socket, params) do
      {:ok, authenticated_socket} -> {:ok, authenticated_socket}
      {:error, reason} -> {:error, {:authentication_failed, reason}}
    end
  end

  defp authorize_tenant_access(socket, tenant_id) do
    case Pipeline.authorize_socket_tenant(socket, tenant_id) do
      {:ok, authorized_socket} -> {:ok, authorized_socket}
      {:error, reason} -> {:error, {:authorization_failed, reason}}
    end
  end

  defp validate_tenant_permissions(socket, tenant_id) do
    user = socket.assigns.current_user

    # Ensure user has at least basic tenant access
    if Authorization.can?(user, :tenant_access, %{tenant_id: tenant_id}) do
      :ok
    else
      {:error, :insufficient_permissions}
    end
  end

  defp has_permission?(socket, permission) do
    permissions = socket.assigns[:tenant_permissions] || []
    permission in permissions
  end

  defp collaboration_permission(resource_type) do
    case resource_type do
      "workflow" -> :workflow_edit
      "effect" -> :effects_edit
      "template" -> :template_manage
      _ -> :workflow_edit  # Default permission
    end
  end

  defp get_initial_tenant_state(tenant_id, user) do
    %{
      tenant_id: tenant_id,
      user_permissions: Authorization.effective_permissions(user.id, tenant_id),
      active_users: get_active_users(tenant_id),
      recent_activities: get_recent_activities(tenant_id),
      workflow_count: get_workflow_count(tenant_id),
      system_status: get_system_status(tenant_id)
    }
  end

  defp create_tenant_workflow(tenant_id, payload, _user) do
    # TODO: Implement workflow creation with tenant context
    {:ok, %{id: Ecto.UUID.generate(), name: payload["name"], tenant_id: tenant_id}}
  end

  defp execute_tenant_workflow(_tenant_id, _workflow_id, _event, _event_data) do
    # TODO: Implement workflow execution
    {:ok, %{status: :executed, result: %{}}}
  end

  defp execute_tenant_effects(_tenant_id, _payload, _user) do
    # TODO: Implement effects execution
    execution_id = Ecto.UUID.generate()
    {:ok, execution_id}
  end

  defp stream_effects_execution(_socket, _execution_id) do
    # TODO: Implement effects execution streaming
    # This would push progress updates to the client
    :ok
  end

  defp apply_collaborative_operation(_tenant_id, _resource_type, _resource_id, _operation, _user) do
    # TODO: Implement collaborative editing operations
    {:ok, %{updated_at: DateTime.utc_now()}}
  end

  defp update_tenant_config(tenant_id, payload, _user) do
    case HybridStore.get(:tenant_config, tenant_id) do
      {:ok, current_config} ->
        updated_config = Map.merge(current_config, payload)
        HybridStore.put(:tenant_config, tenant_id, updated_config)
        {:ok, updated_config}

      {:error, :not_found} ->
        HybridStore.put(:tenant_config, tenant_id, payload)
        {:ok, payload}

      error -> error
    end
  end

  defp get_active_users(tenant_id) do
    FSMAppWeb.Presence.list("tenant:#{tenant_id}")
    |> Enum.map(fn {_user_id, %{metas: [meta | _]}} -> meta.user end)
  end

  defp get_recent_activities(_tenant_id) do
    # TODO: Implement recent activity fetching
    []
  end

  defp get_workflow_count(_tenant_id) do
    # TODO: Implement workflow counting
    0
  end

  defp get_system_status(_tenant_id) do
    # TODO: Implement system status checking
    %{status: :healthy, last_check: DateTime.utc_now()}
  end
end
