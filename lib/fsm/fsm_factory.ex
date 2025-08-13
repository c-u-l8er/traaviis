defmodule FSM.Factory do
  @moduledoc """
  Factory module for creating different types of FSMs using the FSM.Navigator framework.
  """

  require Logger

  @doc """
  Create an FSM instance based on the module name.
  """
  def create_fsm(module_name, config, tenant_id) do
    Logger.info("Creating FSM: #{module_name} for tenant: #{tenant_id}")

    # Add tenant_id to config
    config_with_tenant = Map.put(config, :tenant_id, tenant_id)

    case module_name do
              "SmartDoor" ->
          try do
            # Generate a string ID instead of using make_ref()
            fsm_id = "smart_door_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
            fsm = FSM.SmartDoor.new(config_with_tenant, id: fsm_id, tenant_id: tenant_id)
            Logger.info("SmartDoor FSM created successfully with ID: #{fsm_id}")
            {:ok, fsm}
          rescue
            e ->
              Logger.error("Failed to create SmartDoor FSM: #{inspect(e)}")
              {:error, :creation_failed}
          end

              "SecuritySystem" ->
          # TODO: Implement SecuritySystem FSM
          Logger.warning("SecuritySystem FSM not implemented yet")
          {:error, :not_implemented}

        "Timer" ->
          # TODO: Implement Timer FSM
          Logger.warning("Timer FSM not implemented yet")
          {:error, :not_implemented}

      _ ->
        Logger.error("Unknown FSM module: #{module_name}")
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
end
