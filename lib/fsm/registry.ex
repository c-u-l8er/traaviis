defmodule FSM.Registry do
  @moduledoc """
  Enhanced FSM Registry for inter-FSM communication and management.

  Features:
  - FSM registration and lookup
  - Tenant isolation
  - Performance monitoring
  - Event broadcasting
  - Health checks
  """
  use GenServer
  require Logger

  @type fsm_id :: term()
  @type fsm_module :: module()
  @type fsm_instance :: struct()
  @type tenant_id :: String.t() | nil

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Client API

  @doc """
  Register an FSM instance with the registry.
  """
  @spec register(fsm_id(), fsm_module(), fsm_instance()) :: :ok
  def register(id, module, fsm) do
    GenServer.call(__MODULE__, {:register, id, module, fsm})
  end

  @doc """
  Get an FSM instance by ID.
  """
  @spec get(fsm_id()) :: {:ok, {fsm_module(), fsm_instance()}} | {:error, :not_found}
  def get(id) do
    GenServer.call(__MODULE__, {:get, id})
  end

  @doc """
  Update an FSM instance in the registry.
  """
  @spec update(fsm_id(), fsm_instance()) :: :ok | {:error, :not_found}
  def update(id, fsm) do
    GenServer.call(__MODULE__, {:update, id, fsm})
  end

  @doc """
  Remove an FSM instance from the registry.
  """
  @spec unregister(fsm_id()) :: :ok
  def unregister(id) do
    GenServer.call(__MODULE__, {:unregister, id})
  end

  @doc """
  List all FSMs for a specific tenant.
  """
  @spec list_by_tenant(tenant_id()) :: [{fsm_id(), fsm_module(), fsm_instance()}]
  def list_by_tenant(tenant_id) do
    GenServer.call(__MODULE__, {:list_by_tenant, tenant_id})
  end

  @doc """
  List all FSMs in the registry.
  """
  @spec list_all() :: [{fsm_id(), fsm_module(), fsm_instance()}]
  def list_all() do
    GenServer.call(__MODULE__, :list_all)
  end

  @doc """
  Get statistics about the registry.
  """
  @spec stats() :: map()
  def stats() do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Broadcast an event to all FSMs or FSMs in a specific tenant.
  """
  @spec broadcast(term(), map(), tenant_id() | nil) :: :ok
  def broadcast(event_type, event_data, tenant_id \\ nil) do
    GenServer.cast(__MODULE__, {:broadcast, event_type, event_data, tenant_id})
  end

  @doc """
  Get FSMs by module type.
  """
  @spec get_by_module(module()) :: [{fsm_id(), fsm_instance()}]
  def get_by_module(module) do
    GenServer.call(__MODULE__, {:get_by_module, module})
  end

  # Server callbacks

  @impl true
  def init(_) do
    {:ok, %{
      fsms: %{},
      tenants: %{},
      modules: %{},
      stats: %{
        total_registered: 0,
        total_unregistered: 0,
        current_count: 0,
        last_activity: nil
      }
    }}
  end

  @impl true
  def handle_call({:register, id, module, fsm}, _from, state) do
    # Update FSM metadata
    fsm = %{fsm | metadata: %{fsm.metadata | updated_at: DateTime.utc_now()}}

    # Store FSM
    new_fsms = Map.put(state.fsms, id, {module, fsm})

    # Update tenant index
    tenant_id = fsm.tenant_id
    new_tenants = if tenant_id do
      tenant_fsms = Map.get(state.tenants, tenant_id, [])
      Map.put(state.tenants, tenant_id, [{id, module, fsm} | tenant_fsms])
    else
      state.tenants
    end

    # Update module index
    module_fsms = Map.get(state.modules, module, [])
    new_modules = Map.put(state.modules, module, [{id, fsm} | module_fsms])

    # Update stats
    new_stats = %{state.stats |
      total_registered: state.stats.total_registered + 1,
      current_count: state.stats.current_count + 1,
      last_activity: DateTime.utc_now()
    }

    new_state = %{state |
      fsms: new_fsms,
      tenants: new_tenants,
      modules: new_modules,
      stats: new_stats
    }

    Logger.info("FSM registered: #{inspect(id)} (#{inspect(module)})")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get, id}, _from, state) do
    case Map.get(state.fsms, id) do
      nil -> {:reply, {:error, :not_found}, state}
      result -> {:reply, {:ok, result}, state}
    end
  end

  @impl true
  def handle_call({:update, id, fsm}, _from, state) do
    case Map.get(state.fsms, id) do
      {module, _old_fsm} ->
        # Update FSM
        new_fsms = Map.put(state.fsms, id, {module, fsm})

        # Update tenant index
        tenant_id = fsm.tenant_id
        new_tenants = if tenant_id do
          tenant_fsms = Map.get(state.tenants, tenant_id, [])
          updated_tenant_fsms = Enum.map(tenant_fsms, fn
            {^id, m, _} -> {id, m, fsm}
            other -> other
          end)
          Map.put(state.tenants, tenant_id, updated_tenant_fsms)
        else
          state.tenants
        end

        # Update module index
        module_fsms = Map.get(state.modules, module, [])
        updated_module_fsms = Enum.map(module_fsms, fn
          {^id, _} -> {id, fsm}
          other -> other
        end)
        new_modules = Map.put(state.modules, module, updated_module_fsms)

        new_state = %{state |
          fsms: new_fsms,
          tenants: new_tenants,
          modules: new_modules
        }

        Logger.debug("FSM updated: #{inspect(id)}")
        {:reply, :ok, new_state}

      nil -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:unregister, id}, _from, state) do
    case Map.get(state.fsms, id) do
      {module, fsm} ->
        # Remove from main index
        new_fsms = Map.delete(state.fsms, id)

        # Remove from tenant index
        tenant_id = fsm.tenant_id
        new_tenants = if tenant_id do
          tenant_fsms = Map.get(state.tenants, tenant_id, [])
          filtered_tenant_fsms = Enum.reject(tenant_fsms, fn {fsm_id, _, _} -> fsm_id == id end)
          Map.put(state.tenants, tenant_id, filtered_tenant_fsms)
        else
          state.tenants
        end

        # Remove from module index
        module_fsms = Map.get(state.modules, module, [])
        filtered_module_fsms = Enum.reject(module_fsms, fn {fsm_id, _} -> fsm_id == id end)
        new_modules = Map.put(state.modules, module, filtered_module_fsms)

        # Update stats
        new_stats = %{state.stats |
          total_unregistered: state.stats.total_unregistered + 1,
          current_count: state.stats.current_count - 1,
          last_activity: DateTime.utc_now()
        }

        new_state = %{state |
          fsms: new_fsms,
          tenants: new_tenants,
          modules: new_modules,
          stats: new_stats
        }

        Logger.info("FSM unregistered: #{inspect(id)}")
        {:reply, :ok, new_state}

      nil -> {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:list_by_tenant, tenant_id}, _from, state) do
    tenant_fsms = Map.get(state.tenants, tenant_id, [])
    {:reply, tenant_fsms, state}
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    all_fsms = Map.values(state.fsms)
    {:reply, all_fsms, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_call({:get_by_module, module}, _from, state) do
    module_fsms = Map.get(state.modules, module, [])
    {:reply, module_fsms, state}
  end

  @impl true
  def handle_cast({:broadcast, event_type, event_data, tenant_id}, state) do
    fsms_to_notify = case tenant_id do
      nil -> Map.values(state.fsms)
      _ -> Map.get(state.tenants, tenant_id, []) |> Enum.map(fn {_id, _module, fsm} -> fsm end)
    end

    Enum.each(fsms_to_notify, fn {module, fsm} ->
      if function_exported?(module, :handle_broadcast_event, 3) do
        spawn(fn ->
          module.handle_broadcast_event(fsm, event_type, event_data)
        end)
      end
    end)

    Logger.debug("Broadcasted event #{inspect(event_type)} to #{length(fsms_to_notify)} FSMs")
    {:noreply, state}
  end

  @impl true
  def handle_info({:health_check, from}, state) do
    health_status = %{
      status: :healthy,
      fsm_count: state.stats.current_count,
      last_activity: state.stats.last_activity,
      memory_usage: :erlang.memory(:total)
    }

    send(from, {:health_status, health_status})
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Health check function
  def health_check do
    send(__MODULE__, {:health_check, self()})
    receive do
      {:health_status, status} -> status
    after
      5000 -> {:error, :timeout}
    end
  end
end
