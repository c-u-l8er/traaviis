defmodule FSMAppWeb.ModulesLive do
  use FSMAppWeb, :live_view
  on_mount FSMAppWeb.Auth.OnMountCurrentUser
  on_mount FSMAppWeb.Auth.RequireAuthLive

  def mount(_params, _session, socket) do
    list = available_modules()
    {:ok, assign(socket, page_title: "Modules", list: list, selected: List.first(list))}
  end

  def handle_event("select", %{"name" => name}, socket) do
    {:noreply, assign(socket, selected: Enum.find(socket.assigns.list, &(&1.name == name)))}
  end

  defp available_modules do
    [
      %{name: "SmartDoor", description: "Smart door with security and timer components", states: ["closed","opening","open","closing"], components: ["Timer","Security"]},
      %{name: "SecuritySystem", description: "Security system with monitoring and alarm states", states: ["monitoring","disarmed","alarm"], components: ["Security"]},
      %{name: "Timer", description: "Basic timer with idle, running, paused, and expired states", states: ["idle","running","paused","expired"], components: []}
    ]
  end
end
