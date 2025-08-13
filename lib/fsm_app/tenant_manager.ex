defmodule FSMApp.TenantManager do
  @moduledoc """
  Manages tenant isolation and multi-tenancy features.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{tenants: %{}}}
  end

  @impl true
  def handle_call({:register_tenant, tenant_id, tenant_info}, _from, state) do
    new_state = %{state | tenants: Map.put(state.tenants, tenant_id, tenant_info)}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_tenant, tenant_id}, _from, state) do
    tenant = Map.get(state.tenants, tenant_id)
    {:reply, tenant, state}
  end

  @impl true
  def handle_call({:list_tenants}, _from, state) do
    {:reply, Map.keys(state.tenants), state}
  end

  @impl true
  def handle_cast({:remove_tenant, tenant_id}, state) do
    new_state = %{state | tenants: Map.delete(state.tenants, tenant_id)}
    {:noreply, new_state}
  end
end
