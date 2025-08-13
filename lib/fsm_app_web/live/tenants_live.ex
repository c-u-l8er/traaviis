defmodule FSMAppWeb.TenantsLive do
  use FSMAppWeb, :live_view
  on_mount FSMAppWeb.Auth.OnMountCurrentUser
  on_mount FSMAppWeb.Auth.RequireAuthLive

  alias FSMApp.Tenancy

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Tenants", list: Tenancy.list_tenants(), selected: nil)}
  end

  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, assign(socket, selected: Tenancy.get_tenant!(id))}
  end
end
