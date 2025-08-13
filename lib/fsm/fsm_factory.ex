defmodule FSM.Factory do
  @moduledoc """
  Factory module for creating different types of FSMs using the FSM.Navigator framework.
  """

  require Logger
  alias FSM.ModuleDiscovery

  @doc """
  Create an FSM instance based on the module name.
  """
  def create_fsm(module_name, config, tenant_id) do
    Logger.info("Creating FSM: #{module_name} for tenant: #{tenant_id}")

    # Add tenant_id to config
    config_with_tenant = Map.put(config, :tenant_id, tenant_id)

    with {:ok, module} <- resolve_fsm_module(module_name) do
      try do
        # If the module implements its own id generation, let it.
        # Otherwise, use a readable prefix based on the short name.
        fsm_id =
          case module_name do
            name when is_binary(name) ->
              prefix = name |> String.downcase() |> String.replace(" ", "_")
              "#{prefix}_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
            _ ->
              Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
          end

        fsm = module.new(config_with_tenant, id: fsm_id, tenant_id: tenant_id)
        Logger.info("#{module} FSM created successfully with ID: #{fsm_id}")
        {:ok, fsm}
      rescue
        e ->
          Logger.error("Failed to create #{module} FSM: #{inspect(e)}")
          {:error, :creation_failed}
      end
    else
      {:error, reason} ->
        Logger.error("Unknown or unavailable FSM module '#{module_name}': #{inspect(reason)}")
        {:error, :unknown_module}
    end
  end

  @doc """
  Destroy an FSM instance.
  """
  def destroy_fsm(fsm_id) do
    Logger.info("Destroying FSM: #{fsm_id}")

    case FSM.Registry.get(fsm_id) do
      {:ok, {_module, _fsm}} ->
        # Unregister from registry
        FSM.Registry.unregister(fsm_id)

        Logger.info("FSM destroyed successfully: #{fsm_id}")
        {:ok, fsm_id}

      {:error, :not_found} ->
        Logger.warning("FSM not found for destruction: #{fsm_id}")
        {:error, :not_found}
    end
  end

  # Resolve a short module name (e.g., "SmartDoor") to a fully-qualified FSM module atom.
  defp resolve_fsm_module(module_name) when is_binary(module_name) do
    # First, try a direct alias under FSM.*
    candidate = Module.concat(FSM, module_name)

    cond do
      Code.ensure_loaded?(candidate) and function_exported?(candidate, :new, 2) ->
        {:ok, candidate}

      true ->
        # Fall back to discovered modules by name match
        case Enum.find(ModuleDiscovery.list_available_fsms(), &(&1.name == module_name)) do
          %{module: mod} -> {:ok, mod}
          _ -> {:error, :not_found}
        end
    end
  end

  defp resolve_fsm_module(module) when is_atom(module) do
    if function_exported?(module, :new, 2) do
      {:ok, module}
    else
      {:error, :not_found}
    end
  end
end
