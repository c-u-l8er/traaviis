defmodule FSMAppWeb.TenantsLive do
  use FSMAppWeb, :live_view
  on_mount FSMAppWeb.Auth.OnMountCurrentUser
  on_mount FSMAppWeb.Auth.RequireAuthLive

  alias FSMApp.Tenancy

  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      page_title: "Tenants",
      list: Tenancy.list_tenants(),
      selected: nil,
      current_role: nil,
      form: %{"name" => "", "slug" => ""}
    )}
  end

  def handle_event("select", %{"id" => id}, socket) do
    selected = Tenancy.get_tenant!(id)
    role = current_role(socket, selected.id)
    {:noreply, assign(socket, selected: selected, current_role: role)}
  end

  def handle_event("create", %{"tenant" => params}, socket) do
    case Tenancy.create_tenant(%{name: params["name"], slug: params["slug"]}) do
      {:ok, tenant} ->
        _ = maybe_add_creator_membership(socket, tenant)
        {:noreply,
          socket
          |> assign(list: Tenancy.list_tenants(), selected: tenant, current_role: current_role(socket, tenant.id), form: %{"name" => "", "slug" => ""})
          |> put_flash(:info, "Tenant created")}
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
          socket
          |> put_flash(:error, humanize_errors(changeset))}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create tenant: #{inspect(reason)}")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Tenancy.delete_tenant(id) do
      :ok ->
        {:noreply,
          socket
          |> assign(list: Tenancy.list_tenants(), selected: nil, current_role: nil)
          |> put_flash(:info, "Tenant deleted")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Tenant not found")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  def handle_event("join", %{"id" => id}, %{assigns: %{current_user: %{id: user_id}}} = socket) do
    case Tenancy.add_member(id, user_id, :owner) do
      {:ok, _} ->
        selected = Tenancy.get_tenant!(id)
        {:noreply,
          socket
          |> assign(selected: selected, current_role: :owner)
          |> put_flash(:info, "You were added as owner to this tenant")}
      {:ok, :already_member} ->
        {:noreply, assign(socket, current_role: current_role(socket, id)) |> put_flash(:info, "You are already a member of this tenant")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add you to this tenant")}
    end
  end

  def handle_event("join", _params, socket) do
    {:noreply, put_flash(socket, :error, "You must be signed in to join a tenant")}
  end

  def handle_event("leave", %{"id" => id}, %{assigns: %{current_user: %{id: user_id}}} = socket) do
    case Tenancy.remove_member(id, user_id) do
      :ok ->
        {:noreply,
          socket
          |> assign(current_role: nil)
          |> put_flash(:info, "You left this tenant")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to leave this tenant")}
    end
  end

  defp humanize_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, {msg, _}} ->
      field = field |> to_string() |> String.replace("_", " ")
      "#{field} #{msg}"
    end)
    |> Enum.join(", ")
  end

  defp maybe_add_creator_membership(%{assigns: %{current_user: %{id: user_id}}}, tenant) do
    Tenancy.add_member(tenant.id, user_id, :owner)
  end
  defp maybe_add_creator_membership(_socket, _tenant), do: :ok

  defp current_role(%{assigns: %{current_user: %{id: user_id}}}, tenant_id) do
    Tenancy.get_user_role(tenant_id, user_id)
  end
  defp current_role(_socket, _tenant_id), do: nil
end
