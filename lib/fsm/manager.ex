defmodule FSM.Manager do
  @moduledoc """
  FSM Manager handles the lifecycle and operations of FSMs.

  Features:
  - FSM creation and destruction
  - Batch operations
  - Performance monitoring
  - Tenant management
  - Event routing
  """
  use GenServer
  require Logger

  @type fsm_config :: map()
  @type fsm_id :: term()
  @type tenant_id :: String.t() | nil

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Client API

  @doc """
  Create a new FSM instance.
  """
  @spec create_fsm(module(), fsm_config(), tenant_id()) :: {:ok, fsm_id()} | {:error, term()}
  def create_fsm(module, config, tenant_id \\ nil) do
    GenServer.call(__MODULE__, {:create_fsm, module, config, tenant_id})
  end

  @doc """
  Destroy an FSM instance.
  """
  @spec destroy_fsm(fsm_id()) :: :ok | {:error, term()}
  def destroy_fsm(fsm_id) do
    GenServer.call(__MODULE__, {:destroy_fsm, fsm_id})
  end

  @doc """
  Send an event to an FSM.
  """
  @spec send_event(fsm_id(), term(), map()) :: {:ok, struct()} | {:error, term()}
  def send_event(fsm_id, event, event_data \\ %{}) do
    GenServer.call(__MODULE__, {:send_event, fsm_id, event, event_data})
  end

  @doc """
  Get FSM state and data.
  """
  @spec get_fsm_state(fsm_id()) :: {:ok, map()} | {:error, term()}
  def get_fsm_state(fsm_id) do
    GenServer.call(__MODULE__, {:get_fsm_state, fsm_id})
  end

  @doc """
  Update FSM data.
  """
  @spec update_fsm_data(fsm_id(), map()) :: {:ok, struct()} | {:error, term()}
  def update_fsm_data(fsm_id, new_data) do
    GenServer.call(__MODULE__, {:update_fsm_data, fsm_id, new_data})
  end

  @doc """
  Get all FSMs for a tenant.
  """
  @spec get_tenant_fsms(tenant_id()) :: {:ok, [map()]} | {:error, term()}
  def get_tenant_fsms(tenant_id) do
    GenServer.call(__MODULE__, {:get_tenant_fsms, tenant_id})
  end

  @doc """
  Get FSM performance metrics.
  """
  @spec get_fsm_metrics(fsm_id()) :: {:ok, map()} | {:error, term()}
  def get_fsm_metrics(fsm_id) do
    GenServer.call(__MODULE__, {:get_fsm_metrics, fsm_id})
  end

  @doc """
  Batch send events to multiple FSMs.
  """
  @spec batch_send_events([{fsm_id(), term(), map()}]) :: {:ok, [map()]} | {:error, term()}
  def batch_send_events(events) do
    GenServer.call(__MODULE__, {:batch_send_events, events})
  end

  @doc """
  Get manager statistics.
  """
  @spec get_stats() :: map()
  def get_stats() do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server callbacks

  @impl true
  def init(_) do
    {:ok, %{
      stats: %{
        fsms_created: 0,
        fsms_destroyed: 0,
        events_processed: 0,
        errors: 0,
        start_time: DateTime.utc_now()
      }
    }}
  end

  @impl true
  def handle_call({:create_fsm, module, config, tenant_id}, _from, state) do
    try do
      # Create FSM with configuration
      fsm = module.new(config, tenant_id: tenant_id)

      # Update stats
      new_stats = %{state.stats | fsms_created: state.stats.fsms_created + 1}

      Logger.info("FSM created: #{inspect(fsm.id)} (#{inspect(module)}) for tenant: #{inspect(tenant_id)}")
      {:reply, {:ok, fsm.id}, %{state | stats: new_stats}}

    rescue
      e ->
        Logger.error("Failed to create FSM: #{inspect(e)}")
        new_stats = %{state.stats | errors: state.stats.errors + 1}
        {:reply, {:error, {:creation_failed, e}}, %{state | stats: new_stats}}
    end
  end

  @impl true
  def handle_call({:destroy_fsm, fsm_id}, _from, state) do
    try do
      # Get FSM from registry
      case FSM.Registry.get(fsm_id) do
        {:ok, {_module, _fsm}} ->
          # Unregister from registry
          FSM.Registry.unregister(fsm_id)

          # Update stats
          new_stats = %{state.stats | fsms_destroyed: state.stats.fsms_destroyed + 1}

          Logger.info("FSM destroyed: #{inspect(fsm_id)}")
          {:reply, :ok, %{state | stats: new_stats}}

        {:error, :not_found} ->
          {:reply, {:error, :not_found}, state}
      end

    rescue
      e ->
        Logger.error("Failed to destroy FSM #{inspect(fsm_id)}: #{inspect(e)}")
        new_stats = %{state.stats | errors: state.stats.errors + 1}
        {:reply, {:error, {:destruction_failed, e}}, %{state | stats: new_stats}}
    end
  end

  @impl true
  def handle_call({:send_event, fsm_id, event, event_data}, _from, state) do
    try do
      # Get FSM from registry
      case FSM.Registry.get(fsm_id) do
        {:ok, {module, fsm}} ->
          # Send event to FSM
          case module.navigate(fsm, event, event_data) do
            {:ok, new_fsm} ->
              # Update FSM in registry
              FSM.Registry.update(fsm_id, new_fsm)

              # Update stats
              new_stats = %{state.stats | events_processed: state.stats.events_processed + 1}

              Logger.debug("Event sent to FSM #{inspect(fsm_id)}: #{inspect(event)}")
              {:reply, {:ok, new_fsm}, %{state | stats: new_stats}}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end

        {:error, :not_found} ->
          {:reply, {:error, :not_found}, state}
      end

    rescue
      e ->
        Logger.error("Failed to send event to FSM #{inspect(fsm_id)}: #{inspect(e)}")
        new_stats = %{state.stats | errors: state.stats.errors + 1}
        {:reply, {:error, {:event_failed, e}}, %{state | stats: new_stats}}
    end
  end

  @impl true
  def handle_call({:get_fsm_state, fsm_id}, _from, state) do
    case FSM.Registry.get(fsm_id) do
      {:ok, {_module, fsm}} ->
        state_info = %{
          id: fsm.id,
          current_state: fsm.current_state,
          data: fsm.data,
          tenant_id: fsm.tenant_id,
          metadata: fsm.metadata,
          performance: fsm.performance
        }
        {:reply, {:ok, state_info}, state}

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:update_fsm_data, fsm_id, new_data}, _from, state) do
    case FSM.Registry.get(fsm_id) do
      {:ok, {_module, fsm}} ->
        # Update FSM data
        updated_fsm = %{fsm | data: Map.merge(fsm.data, new_data)}

        # Update in registry
        FSM.Registry.update(fsm_id, updated_fsm)

        Logger.debug("FSM data updated: #{inspect(fsm_id)}")
        {:reply, {:ok, updated_fsm}, state}

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_tenant_fsms, tenant_id}, _from, state) do
    tenant_fsms = FSM.Registry.list_by_tenant(tenant_id)

    fsm_summaries = Enum.map(tenant_fsms, fn {id, module, fsm} ->
      %{
        id: id,
        module: module,
        current_state: fsm.current_state,
        tenant_id: fsm.tenant_id,
        metadata: fsm.metadata
      }
    end)

    {:reply, {:ok, fsm_summaries}, state}
  end

  @impl true
  def handle_call({:get_fsm_metrics, fsm_id}, _from, state) do
    case FSM.Registry.get(fsm_id) do
      {:ok, {_module, fsm}} ->
        metrics = %{
          id: fsm.id,
          performance: fsm.performance,
          metadata: fsm.metadata
        }
        {:reply, {:ok, metrics}, state}

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:batch_send_events, events}, _from, state) do
    results = Enum.map(events, fn {fsm_id, event, event_data} ->
      case send_event(fsm_id, event, event_data) do
        {:ok, fsm} -> {:ok, fsm_id, fsm}
        {:error, reason} -> {:error, fsm_id, reason}
      end
    end)

    # Update stats
    new_stats = %{state.stats | events_processed: state.stats.events_processed + length(events)}

    {:reply, {:ok, results}, %{state | stats: new_stats}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    registry_stats = FSM.Registry.stats()

    combined_stats = Map.merge(state.stats, %{
      registry_stats: registry_stats,
      uptime: DateTime.diff(DateTime.utc_now(), state.stats.start_time, :second)
    })

    {:reply, combined_stats, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
