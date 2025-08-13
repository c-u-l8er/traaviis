defmodule FSMAppWeb.MembersLive do
  use FSMAppWeb, :live_view
  on_mount FSMAppWeb.Auth.OnMountCurrentUser
  on_mount FSMAppWeb.Auth.RequireAuthLive

  alias FSMApp.Tenancy

  def mount(_params, _session, socket) do
    tenants = Tenancy.list_tenants()
    members = case tenants do
      [t | _] -> Tenancy.list_members(t.id)
      _ -> []
    end
    {:ok, assign(socket, page_title: "Members", tenants: tenants, list: members, selected: nil)}
  end

  def handle_event("select_tenant", %{"tenant_id" => id}, socket) do
    {:noreply, assign(socket, list: Tenancy.list_members(id), selected: nil)}
  end

  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, assign(socket, selected: Enum.find(socket.assigns.list, &(&1.id == id)))}
  end
end
