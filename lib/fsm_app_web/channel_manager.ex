defmodule FSMAppWeb.ChannelManager do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_info({:channel_event, event_type, data}, state) do
    Logger.info("Channel event: #{event_type} - #{inspect(data)}")
    {:noreply, state}
  end

  @impl true
  def handle_call({:get_channel_info, channel_id}, _from, state) do
    # Return channel information
    {:reply, {:ok, %{id: channel_id, status: :active}}, state}
  end

  @impl true
  def handle_cast({:broadcast_to_channel, channel_id, event, payload}, state) do
    Phoenix.PubSub.broadcast!(FSMApp.PubSub, "fsm:#{channel_id}", event, payload)
    {:noreply, state}
  end
end
