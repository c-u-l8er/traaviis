defmodule FSMApp.MCP.ClientManager do
  @moduledoc """
  Manages MCP client connections and operations.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{clients: %{}}}
  end

  @impl true
  def handle_call({:register_client, client_id, client_info}, _from, state) do
    new_state = %{state | clients: Map.put(state.clients, client_id, client_info)}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_client, client_id}, _from, state) do
    client = Map.get(state.clients, client_id)
    {:reply, client, state}
  end

  @impl true
  def handle_call({:list_clients}, _from, state) do
    {:reply, Map.keys(state.clients), state}
  end

  @impl true
  def handle_cast({:remove_client, client_id}, state) do
    new_state = %{state | clients: Map.delete(state.clients, client_id)}
    {:noreply, new_state}
  end
end
