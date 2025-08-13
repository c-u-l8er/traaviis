defmodule FSMAppWeb.FSMSLive do
  use FSMAppWeb, :live_view
  on_mount FSMAppWeb.Auth.OnMountCurrentUser
  on_mount FSMAppWeb.Auth.RequireAuthLive

  alias FSM.Registry
  alias FSM.Manager

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "FSMs", selected: nil, list: list_fsms(), tenant_id: nil)}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    {:noreply, assign(socket, selected: get_fsm(id))}
  end
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/fsms/#{id}")}
  end

  defp list_fsms() do
    Registry.list() |> Enum.map(fn {id, {mod, fsm}} -> %{id: id, module: mod, state: fsm.current_state} end)
  end

  defp get_fsm(id) do
    case Registry.get(id) do
      {:ok, {mod, fsm}} -> %{id: id, module: mod, data: fsm.data, state: fsm.current_state}
      _ -> nil
    end
  end
end
