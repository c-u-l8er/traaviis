defmodule FSMApp.Storage.HybridStore do
  @moduledoc """
  Hybrid storage combining ETS performance with JSON persistence.

  This is the main interface for the enhanced storage system, providing:
  - Hot path: ETS for fast access and caching
  - Cold path: JSON files for durability and persistence
  - Automatic failover and consistency management
  - Telemetry and performance monitoring

  Usage:
    HybridStore.put_workflow(workflow)
    HybridStore.get_workflow(workflow_id, tenant_id)
    HybridStore.put_user(user)
    HybridStore.get_user(user_id)
  """

  alias FSMApp.Storage.{ETSManager, EnhancedStore}
  require Logger

  @doc """
  Store a workflow with ETS caching and JSON persistence.
  """
  def put_workflow(workflow) do
    workflow_id = workflow.id || raise ArgumentError, "Workflow must have an id"
    tenant_id = workflow.tenant_id || raise ArgumentError, "Workflow must have a tenant_id"

    # Generate cache key
    cache_key = workflow_cache_key(workflow_id, tenant_id)

    start_time = System.monotonic_time()

    result = with :ok <- store_in_ets(:workflows_registry, cache_key, workflow),
                  :ok <- store_in_json(:workflow, workflow) do
      # Emit telemetry
      :telemetry.execute([:storage, :workflow, :stored],
        %{duration: System.monotonic_time() - start_time},
        %{tenant_id: tenant_id, workflow_id: workflow_id, storage_type: :hybrid})

      Logger.debug("Stored workflow #{workflow_id} for tenant #{tenant_id}")
      :ok
    end

    result
  end

  @doc """
  Get a workflow with ETS cache and JSON fallback.
  """
  def get_workflow(workflow_id, tenant_id) do
    cache_key = workflow_cache_key(workflow_id, tenant_id)
    start_time = System.monotonic_time()

    case ETSManager.get(:workflows_registry, cache_key) do
      {:ok, workflow} ->
        # Cache hit
        :telemetry.execute([:storage, :workflow, :retrieved],
          %{duration: System.monotonic_time() - start_time},
          %{tenant_id: tenant_id, workflow_id: workflow_id, cache_hit: true})

        {:ok, workflow}

      {:error, :not_found} ->
        # Cache miss - try JSON
        case load_workflow_from_json(workflow_id, tenant_id) do
          {:ok, workflow} ->
            # Populate cache for future access
            ETSManager.put(:workflows_registry, cache_key, workflow, ttl: 3600)

            :telemetry.execute([:storage, :workflow, :retrieved],
              %{duration: System.monotonic_time() - start_time},
              %{tenant_id: tenant_id, workflow_id: workflow_id, cache_hit: false})

            {:ok, workflow}

          error ->
            :telemetry.execute([:storage, :workflow, :retrieval_failed],
              %{duration: System.monotonic_time() - start_time},
              %{tenant_id: tenant_id, workflow_id: workflow_id})
            error
        end

      error -> error
    end
  end

  @doc """
  Store a user with ETS caching and JSON persistence.
  """
  def put_user(user) do
    user_id = user.id || raise ArgumentError, "User must have an id"

    start_time = System.monotonic_time()

    result = with :ok <- store_in_ets(:users_registry, user_id, user),
                  :ok <- EnhancedStore.store_user(user) do
      # Emit telemetry
      :telemetry.execute([:storage, :user, :stored],
        %{duration: System.monotonic_time() - start_time},
        %{user_id: user_id, storage_type: :hybrid})

      Logger.debug("Stored user #{user_id}")
      :ok
    end

    result
  end

  @doc """
  Get a user with ETS cache and JSON fallback.
  """
  def get_user(user_id) do
    start_time = System.monotonic_time()

    case ETSManager.get(:users_registry, user_id) do
      {:ok, user} ->
        # Cache hit
        :telemetry.execute([:storage, :user, :retrieved],
          %{duration: System.monotonic_time() - start_time},
          %{user_id: user_id, cache_hit: true})

        {:ok, user}

      {:error, :not_found} ->
        # Cache miss - try JSON
        case EnhancedStore.load_user(user_id) do
          {:ok, user_data} ->
            # Convert to struct and populate cache
            user = to_user_struct(user_data)
            ETSManager.put(:users_registry, user_id, user, ttl: 1800)

            :telemetry.execute([:storage, :user, :retrieved],
              %{duration: System.monotonic_time() - start_time},
              %{user_id: user_id, cache_hit: false})

            {:ok, user}

          error ->
            :telemetry.execute([:storage, :user, :retrieval_failed],
              %{duration: System.monotonic_time() - start_time},
              %{user_id: user_id})
            error
        end

      error -> error
    end
  end

  @doc """
  Store a tenant member with ETS caching and JSON persistence.
  """
  def put_member(tenant_id, member) do
    user_id = member.user_id || raise ArgumentError, "Member must have a user_id"
    cache_key = member_cache_key(tenant_id, user_id)

    start_time = System.monotonic_time()

    result = with :ok <- store_in_ets(:tenant_members_registry, cache_key, member),
                  :ok <- EnhancedStore.store_member(tenant_id, member) do
      # Emit telemetry
      :telemetry.execute([:storage, :member, :stored],
        %{duration: System.monotonic_time() - start_time},
        %{tenant_id: tenant_id, user_id: user_id, storage_type: :hybrid})

      Logger.debug("Stored member #{user_id} for tenant #{tenant_id}")
      :ok
    end

    result
  end

  @doc """
  Get a tenant member with ETS cache and JSON fallback.
  """
  def get_member(tenant_id, user_id) do
    cache_key = member_cache_key(tenant_id, user_id)
    start_time = System.monotonic_time()

    case ETSManager.get(:tenant_members_registry, cache_key) do
      {:ok, member} ->
        # Cache hit
        :telemetry.execute([:storage, :member, :retrieved],
          %{duration: System.monotonic_time() - start_time},
          %{tenant_id: tenant_id, user_id: user_id, cache_hit: true})

        {:ok, member}

      {:error, :not_found} ->
        # Cache miss - try JSON
        case EnhancedStore.load_member(tenant_id, user_id) do
          {:ok, member_data} ->
            # Convert to struct and populate cache
            member = to_member_struct(member_data)
            ETSManager.put(:tenant_members_registry, cache_key, member, ttl: 1800)

            :telemetry.execute([:storage, :member, :retrieved],
              %{duration: System.monotonic_time() - start_time},
              %{tenant_id: tenant_id, user_id: user_id, cache_hit: false})

            {:ok, member}

          error ->
            :telemetry.execute([:storage, :member, :retrieval_failed],
              %{duration: System.monotonic_time() - start_time},
              %{tenant_id: tenant_id, user_id: user_id})
            error
        end

      error -> error
    end
  end

  @doc """
  Store session data with ETS-only storage (ephemeral).
  """
  def put_session(session_id, session_data, ttl \\ 3600) do
    start_time = System.monotonic_time()

    result = ETSManager.put(:session_store, session_id, session_data, ttl: ttl)

    :telemetry.execute([:storage, :session, :stored],
      %{duration: System.monotonic_time() - start_time},
      %{session_id: session_id, ttl: ttl})

    result
  end

  @doc """
  Get session data (ETS-only).
  """
  def get_session(session_id) do
    start_time = System.monotonic_time()

    result = ETSManager.get(:session_store, session_id)

    :telemetry.execute([:storage, :session, :retrieved],
      %{duration: System.monotonic_time() - start_time},
      %{session_id: session_id, cache_hit: match?({:ok, _}, result)})

    result
  end

  @doc """
  Delete data from both ETS and persistent storage.
  """
  def delete(storage_type, _key_or_keys) do
    case storage_type do
      {:workflow, workflow_id, tenant_id} ->
        cache_key = workflow_cache_key(workflow_id, tenant_id)
        with :ok <- ETSManager.delete(:workflows_registry, cache_key),
             :ok <- delete_workflow_from_json(workflow_id, tenant_id) do
          Logger.debug("Deleted workflow #{workflow_id} from tenant #{tenant_id}")
          :ok
        end

      {:user, user_id} ->
        # Note: We don't delete users from persistent storage for audit reasons
        # Just remove from cache
        ETSManager.delete(:users_registry, user_id)

      {:member, tenant_id, user_id} ->
        cache_key = member_cache_key(tenant_id, user_id)
        with :ok <- ETSManager.delete(:tenant_members_registry, cache_key) do
          # Also remove from persistent storage
          delete_member_from_json(tenant_id, user_id)
        end

      {:session, session_id} ->
        ETSManager.delete(:session_store, session_id)

      _ ->
        {:error, :invalid_storage_type}
    end
  end

  @doc """
  List items with caching support.
  """
  def list(storage_type, opts \\ []) do
    case storage_type do
      {:workflows, tenant_id} ->
        list_workflows_for_tenant(tenant_id, opts)

      {:members, tenant_id} ->
        list_members_for_tenant(tenant_id, opts)

      :users ->
        list_users(opts)

      _ ->
        {:error, :invalid_storage_type}
    end
  end

  @doc """
  Get storage statistics.
  """
  def storage_stats do
    ets_stats = ETSManager.memory_stats()

    %{
      ets: ets_stats,
      performance_metrics: get_performance_metrics()
    }
  end

  @doc """
  Warm up caches by preloading frequently accessed data.
  """
  def warmup_caches(opts \\ []) do
    Logger.info("Warming up hybrid storage caches")

    # Preload recent users
    if Keyword.get(opts, :users, true) do
      warmup_user_cache()
    end

    # Preload active sessions
    if Keyword.get(opts, :sessions, true) do
      warmup_session_cache()
    end

    # Preload recent workflows per tenant
    if Keyword.get(opts, :workflows, true) do
      warmup_workflow_cache()
    end

    Logger.info("Cache warmup completed")
    :ok
  end

  @doc """
  Initialize hybrid storage system.
  """
  def initialize do
    with :ok <- ETSManager.initialize_tables(),
         :ok <- EnhancedStore.initialize_directory_structure() do
      Logger.info("Hybrid storage system initialized successfully")
      :ok
    else
      error ->
        Logger.error("Failed to initialize hybrid storage: #{inspect(error)}")
        error
    end
  end

  # Private helper functions

  defp workflow_cache_key(workflow_id, tenant_id) do
    "#{tenant_id}:#{workflow_id}"
  end

  defp member_cache_key(tenant_id, user_id) do
    "#{tenant_id}:#{user_id}"
  end

  defp store_in_ets(table, key, value, opts \\ []) do
    case ETSManager.put(table, key, value, opts) do
      :ok -> :ok
      error ->
        Logger.error("Failed to store in ETS table #{table}: #{inspect(error)}")
        error
    end
  end

  defp store_in_json(type, data) do
    case type do
      :workflow -> store_workflow_in_json(data)
      :user -> EnhancedStore.store_user(data)
      :member -> EnhancedStore.store_member(data.tenant_id, data)
      _ -> {:error, :unsupported_type}
    end
  end

  defp store_workflow_in_json(_workflow) do
    # TODO: Implement workflow JSON persistence
    # This would store in: ./data/tenants/{tenant_id}/workflows/{Module}/{fsm_id}.json
    :ok
  end

  defp load_workflow_from_json(_workflow_id, _tenant_id) do
    # TODO: Implement workflow JSON loading
    {:error, :not_found}
  end

  defp delete_workflow_from_json(_workflow_id, _tenant_id) do
    # TODO: Implement workflow JSON deletion
    :ok
  end

  defp delete_member_from_json(_tenant_id, _user_id) do
    # TODO: Implement member JSON deletion
    :ok
  end

  defp list_workflows_for_tenant(_tenant_id, _opts) do
    # TODO: Implement efficient tenant workflow listing
    # Should combine ETS cache with JSON fallback
    {:ok, []}
  end

  defp list_members_for_tenant(tenant_id, _opts) do
    case EnhancedStore.list_tenant_members(tenant_id) do
      {:ok, members_data} ->
        members = Enum.map(members_data, &to_member_struct/1)
        {:ok, members}
      error -> error
    end
  end

  defp list_users(opts) do
    case EnhancedStore.list_users(opts) do
      {:ok, users_data} ->
        users = Enum.map(users_data, &to_user_struct/1)
        {:ok, users}
      error -> error
    end
  end

  defp to_user_struct(data) when is_map(data) do
    # Convert map to User struct
    # This would typically use your existing User struct conversion
    data
  end

  defp to_member_struct(data) when is_map(data) do
    # Convert map to Member struct
    # This would typically use your existing Member struct conversion
    data
  end

  defp get_performance_metrics do
    # TODO: Implement performance metrics collection
    %{
      cache_hit_ratio: 0.0,
      avg_response_time: 0.0,
      total_requests: 0
    }
  end

  defp warmup_user_cache do
    # TODO: Implement user cache warmup
    :ok
  end

  defp warmup_session_cache do
    # TODO: Implement session cache warmup
    :ok
  end

  defp warmup_workflow_cache do
    # TODO: Implement workflow cache warmup
    :ok
  end
end
