defmodule FSMAppWeb.MembersLive do
  use FSMAppWeb, :live_view
  on_mount FSMAppWeb.Auth.OnMountCurrentUser
  on_mount FSMAppWeb.Auth.RequireAuthLive

  alias FSMApp.Tenancy

  def mount(_params, _session, socket) do
    tenants = assigned_tenants(socket)
    {selected_tenant_id, members} = case tenants do
      [%{id: tid} | _] -> {tid, Tenancy.list_members(tid)}
      _ -> {nil, []}
    end
    {:ok, assign(socket, page_title: "Members", tenants: tenants, selected_tenant_id: selected_tenant_id, list: members, selected: nil)}
  end

  def handle_event("select_tenant", %{"tenant_id" => id}, socket) do
    {:noreply, assign(socket, selected_tenant_id: id, list: Tenancy.list_members(id), selected: nil)}
  end

  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, assign(socket, selected: Enum.find(socket.assigns.list, &(&1.id == id)))}
  end

  defp assigned_tenants(%{assigns: %{current_user: nil}}), do: []
  defp assigned_tenants(%{assigns: %{current_user: current_user}}) do
    Tenancy.list_user_tenants(current_user.id)
  end
end
