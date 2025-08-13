defmodule FSMAppWeb.ModulesLive do
  use FSMAppWeb, :live_view
  on_mount FSMAppWeb.Auth.OnMountCurrentUser
  on_mount FSMAppWeb.Auth.RequireAuthLive
  alias FSM.ModuleDiscovery

  def mount(_params, _session, socket) do
    list = available_modules()
    {:ok, assign(socket, page_title: "Modules", list: list, selected: List.first(list))}
  end

  def handle_event("select", %{"name" => name}, socket) do
    {:noreply, assign(socket, selected: Enum.find(socket.assigns.list, &(&1.name == name)))}
  end

  defp available_modules do
    ModuleDiscovery.list_available_fsms()
    |> Enum.map(fn m -> Map.merge(%{states: [], components: []}, m) end)
  end
end
