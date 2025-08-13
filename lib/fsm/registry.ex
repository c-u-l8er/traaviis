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
  Reload FSM registry state from persisted JSON files on disk.

  Useful when new FSM JSON files are added to the `data/` directory while the
  application is running, or when module names have changed and need remapping.
  """
  @spec reload_from_disk() :: :ok | {:error, term()}
  def reload_from_disk() do
    GenServer.call(__MODULE__, :reload_from_disk)
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
    case load_state_from_json() do
      {:ok, state} -> {:ok, state}
      :error ->
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
    persist_fsm_to_file(id, module, fsm)
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
        persist_fsm_to_file(id, module, fsm)
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
        delete_fsm_file(id)
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
  def handle_call(:reload_from_disk, _from, _state) do
    case load_state_from_json() do
      {:ok, new_state} ->
        require Logger
        Logger.info("FSM.Registry reloaded state from disk (#{map_size(new_state.fsms)} fsms)")
        {:reply, :ok, new_state}
      :error ->
        {:reply, {:error, :load_failed}, %{fsms: %{}, tenants: %{}, modules: %{}, stats: %{total_registered: 0, total_unregistered: 0, current_count: 0, last_activity: nil}}}
    end
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

  # JSON persistence helpers (./data/*.json)
  defp data_dir, do: Path.expand("data")

  defp fsm_file_path(id), do: Path.join(data_dir(), "#{id}.json")

  defp persist_fsm_to_file(id, module, fsm) do
    File.mkdir_p!(data_dir())
    json_map = serialize_fsm_for_json(module, fsm)
    case Jason.encode(json_map, pretty: true) do
      {:ok, json} -> File.write(fsm_file_path(id), json)
      {:error, reason} -> Logger.error("Failed to encode FSM #{inspect(id)} to JSON: #{inspect(reason)}")
    end
  end

  defp delete_fsm_file(id) do
    _ = File.rm(fsm_file_path(id))
    :ok
  end

  defp load_state_from_json do
    dir = data_dir()
    case File.ls(dir) do
      {:ok, files} ->
        fsms =
          files
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.reduce(%{}, fn file, acc ->
            path = Path.join(dir, file)
            with {:ok, bin} <- File.read(path),
                 {:ok, map} <- Jason.decode(bin),
                 {:ok, {id, module, fsm}} <- deserialize_fsm_from_json(map) do
              Map.put(acc, id, {module, fsm})
            else
              _ -> acc
            end
          end)

        tenants =
          fsms
          |> Enum.reduce(%{}, fn {id, {module, fsm}}, acc ->
            if fsm.tenant_id do
              tenant_fsms = Map.get(acc, fsm.tenant_id, [])
              Map.put(acc, fsm.tenant_id, [{id, module, fsm} | tenant_fsms])
            else
              acc
            end
          end)

        modules =
          fsms
          |> Enum.reduce(%{}, fn {id, {module, fsm}}, acc ->
            module_fsms = Map.get(acc, module, [])
            Map.put(acc, module, [{id, fsm} | module_fsms])
          end)

        stats = %{
          total_registered: map_size(fsms),
          total_unregistered: 0,
          current_count: map_size(fsms),
          last_activity: DateTime.utc_now()
        }

        {:ok, %{fsms: fsms, tenants: tenants, modules: modules, stats: stats}}

      {:error, _} -> :error
    end
  end

  defp serialize_fsm_for_json(module, fsm) do
    %{
      id: fsm.id,
      module: Atom.to_string(module),
      tenant_id: fsm.tenant_id,
      current_state: Atom.to_string(fsm.current_state),
      data: sanitize_for_json(Map.delete(fsm.data || %{}, :timers)),
      metadata: %{
        created_at: datetime_to_iso8601(fsm.metadata.created_at),
        updated_at: datetime_to_iso8601(fsm.metadata.updated_at),
        version: fsm.metadata.version,
        tags: fsm.metadata.tags
      },
      performance: %{
        transition_count: fsm.performance.transition_count,
        last_transition_at: datetime_to_iso8601(fsm.performance.last_transition_at),
        avg_transition_time: fsm.performance.avg_transition_time
      },
      subscribers: fsm.subscribers,
      plugins: Enum.map(fsm.plugins, fn {mod, opts} ->
        %{
          module: Atom.to_string(mod),
          opts: sanitize_for_json(Enum.into(opts, %{}))
        }
      end)
    }
  end

  # Deep sanitize any structure into JSON-friendly values (strings, numbers, booleans, null, arrays, objects)
  defp sanitize_for_json(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {to_string(k), sanitize_for_json(v)} end)
    |> Enum.into(%{})
  end
  defp sanitize_for_json(value) when is_list(value) do
    # Convert keyword lists or plain lists
    cond do
      Keyword.keyword?(value) ->
        value
        |> Enum.into(%{})
        |> sanitize_for_json()
      true -> Enum.map(value, &sanitize_for_json/1)
    end
  end
  defp sanitize_for_json(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&sanitize_for_json/1)
  end
  defp sanitize_for_json(value) when is_atom(value) do
    case value do
      true -> true
      false -> false
      nil -> nil
      _ -> Atom.to_string(value)
    end
  end
  defp sanitize_for_json(%DateTime{} = dt), do: datetime_to_iso8601(dt)
  defp sanitize_for_json(other), do: other

  defp datetime_to_iso8601(nil), do: nil
  defp datetime_to_iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp deserialize_fsm_from_json(%{
         "id" => id,
         "module" => module_str,
         "tenant_id" => tenant_id,
         "current_state" => current_state_str,
         "data" => data,
         "metadata" => meta,
         "performance" => perf,
         "subscribers" => subscribers,
         "plugins" => plugins
       }) do
    try do
      module = resolve_module(module_str)
      current_state = String.to_existing_atom(current_state_str)
      created_at = parse_datetime(meta["created_at"])
      updated_at = parse_datetime(meta["updated_at"])
      last_transition_at = parse_datetime(perf["last_transition_at"])

      fsm = struct(module, %{
        id: id,
        tenant_id: tenant_id,
        current_state: current_state,
        data: data || %{},
        subscribers: subscribers || [],
        plugins: Enum.map(plugins || [], fn
          %{"module" => mod_str, "opts" => opts} -> {String.to_existing_atom(mod_str), json_opts_to_keyword(opts)}
          [mod_str, opts] -> {String.to_existing_atom(mod_str), json_opts_to_keyword(opts)}
        end),
        metadata: %{
          created_at: created_at,
          updated_at: updated_at,
          version: meta["version"],
          tags: meta["tags"] || []
        },
        performance: %{
          transition_count: perf["transition_count"] || 0,
          last_transition_at: last_transition_at,
          avg_transition_time: perf["avg_transition_time"] || 0
        }
      })

      {:ok, {id, module, fsm}}
    rescue
      _ -> :error
    end
  end
  defp deserialize_fsm_from_json(_), do: :error

  # Gracefully resolve module names from persisted JSON, handling historical names
  # like "SecuritySystem" or "Elixir.SecuritySystem" by mapping them to
  # namespaced modules under FSM.*.
  defp resolve_module(module_str) when is_binary(module_str) do
    # Try the exact module string first
    try do
      String.to_existing_atom(module_str)
    rescue
      _ ->
        # Try remapping common core names into the FSM namespace
        base =
          module_str
          |> String.replace_prefix("Elixir.", "")

        candidate_names = [
          "Elixir.FSM." <> base,
          "Elixir." <> base
        ]

        Enum.find_value(candidate_names, fn name ->
          try do
            String.to_existing_atom(name)
          rescue
            _ -> nil
          end
        end) ||
        # Last-chance explicit mappings for well-known cores
        case base do
          "SecuritySystem" -> FSM.SecuritySystem
          "SmartDoor" -> FSM.SmartDoor
          "Timer" -> FSM.Timer
          _ -> raise ArgumentError
        end
    end
  end

  defp json_opts_to_keyword(opts) when is_map(opts) do
    opts
    |> Enum.map(fn {k, v} ->
      key_atom = safe_to_existing_atom(k)
      {key_atom || String.to_atom(k), string_to_existing_atom_or_value(v)}
    end)
  end
  defp json_opts_to_keyword(opts) when is_list(opts), do: Enum.map(opts, &string_to_existing_atom_or_value/1)
  defp json_opts_to_keyword(other), do: other

  defp string_to_existing_atom_or_value(v) when is_binary(v) do
    try do
      String.to_existing_atom(v)
    rescue
      _ -> v
    end
  end
  defp string_to_existing_atom_or_value(v), do: v

  defp safe_to_existing_atom(k) do
    try do
      String.to_existing_atom(to_string(k))
    rescue
      _ -> nil
    end
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
