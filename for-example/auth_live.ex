defmodule BrokenRecordWeb.AuthLive do
  @moduledoc """
  Authentication LiveView for login and registration.

  Handles user authentication and initial tenant selection for multi-tenant users.
  """
  use BrokenRecordWeb, :live_view
  require Logger

  alias BrokenRecord.Accounts
  alias BrokenRecord.Tenants
  alias BrokenRecord.Guardian
  alias BrokenRecordWeb.Components.Logo

  @impl true
  def mount(_params, _session, socket) do
    changeset = %{
      "email" => "",
      "password" => "",
      "name" => "",
      "organization" => ""
    }

    socket =
      socket
      |> assign(:form, to_form(changeset, as: :auth))
      |> assign(:page_title, "BrokenRecord PaaS - Login")
      |> assign(:mode, :login)
      |> assign(:loading, false)
      |> assign(:current_user, nil)
      |> assign(:user_tenants, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"mode" => "register"}, _uri, socket) do
    {:noreply, assign(socket, :mode, :register)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :mode, :login)}
  end

  @impl true
  def handle_event("toggle_mode", _params, socket) do
    new_mode = if socket.assigns.mode == :login, do: :register, else: :login

    # Preserve form data when toggling modes
    socket = assign(socket, :mode, new_mode)

    {:noreply, push_patch(socket, to: ~p"/auth?mode=#{new_mode}")}
  end

  def handle_event("validate", %{"auth" => params}, socket) do
    # Preserve the form data without losing input values
    form = to_form(params, as: :auth, action: :validate)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("submit", %{"auth" => params}, socket) do
    IO.puts("=== FORM SUBMIT ===")
    IO.inspect(params, label: "Params")
    IO.inspect(socket.assigns.mode, label: "Mode")

    socket = assign(socket, :loading, true)

    case socket.assigns.mode do
      :login -> handle_login(params, socket)
      :register -> handle_registration(params, socket)
    end
  end

  # Handle submission without auth params (shouldn't happen but safety first)
  def handle_event("submit", _params, socket) do
    form = to_form(%{}, as: :auth, errors: [base: "Invalid form submission"])
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:form, form)
     |> put_flash(:error, "Please fill out the form correctly.")}
  end

  def handle_event("select_tenant", %{"tenant_id" => tenant_id}, socket) do
    user = socket.assigns.current_user

    case Guardian.create_tenant_token(user, tenant_id) do
      {:ok, token, _claims} ->
        {:noreply,
         socket
         |> put_flash(:info, "Welcome to your tenant dashboard!")
         |> redirect(to: ~p"/dashboard?token=#{token}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> put_flash(:error, "Failed to access tenant: #{reason}")}
    end
  end

  # Private functions

  defp handle_login(%{"email" => email, "password" => password} = params, socket) when email != "" and password != "" do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        # Get user's tenant memberships
        tenants = get_user_tenants(user.id)

        case tenants do
          [] ->
            # No tenants - show tenant creation or contact admin
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:current_user, user)
             |> assign(:user_tenants, [])
             |> put_flash(:info, "No tenant access found. Contact your administrator or create a new organization.")}

          [tenant] ->
            # Single tenant - log in directly
            case Guardian.create_tenant_token(user, tenant.tenant_id) do
              {:ok, token, _claims} ->
                {:noreply,
                 socket
                 |> put_flash(:info, "Welcome back, #{user.name}!")
                 |> redirect(to: ~p"/dashboard?token=#{token}")}

              {:error, reason} ->
                {:noreply,
                 socket
                 |> assign(:loading, false)
                 |> put_flash(:error, "Login failed: #{reason}")}
            end

          multiple_tenants ->
            # Multiple tenants - show selection
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:current_user, user)
             |> assign(:user_tenants, multiple_tenants)}
        end

      {:error, :invalid_credentials} ->
        form = to_form(params, as: :auth, errors: [base: "Invalid email or password"])
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:form, form)
         |> put_flash(:error, "Invalid email or password")}

      {:error, :user_suspended} ->
        form = to_form(params, as: :auth, errors: [base: "Account suspended"])
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:form, form)
         |> put_flash(:error, "🚫 Your account has been suspended. Please contact support for assistance.")}

      {:error, :user_not_verified} ->
        form = to_form(params, as: :auth, errors: [base: "Email not verified"])
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:form, form)
         |> put_flash(:error, "Please verify your email address before logging in.")}

      {:error, _reason} ->
        form = to_form(params, as: :auth, errors: [base: "Login failed"])
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:form, form)
         |> put_flash(:error, "Login failed. Please try again.")}
    end
  end

    # Handle login with missing or empty fields
  defp handle_login(params, socket) do
    IO.puts("=== LOGIN VALIDATION ===")
    IO.inspect(params, label: "Login params")

    errors = []
    errors = if Map.get(params, "email", "") == "", do: [{:email, "is required"} | errors], else: errors
    errors = if Map.get(params, "password", "") == "", do: [{:password, "is required"} | errors], else: errors

    IO.inspect(errors, label: "Login errors")

    form = to_form(params, as: :auth, errors: errors)
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:form, form)
     |> put_flash(:error, "Please fill out all required fields.")}
  end

  defp handle_registration(%{"email" => email, "password" => password, "name" => name, "organization" => org_name} = params, socket)
    when email != "" and password != "" and name != "" and org_name != "" do
    # Create user account
    case Accounts.create_user(%{
      email: email,
      password: password,
      name: name
    }) do
      {:ok, user} ->
        # Create initial tenant/organization
        case Tenants.create_tenant(%{
          name: org_name,
          owner_id: user.id,
          billing_plan: "starter"
        }) do
          {:ok, tenant} ->
            # Add user as owner
            case Tenants.add_member(tenant.id, user.id, %{tenant_role: :owner}) do
              {:ok, _member} ->
                # Create tenant token and log in
                case Guardian.create_tenant_token(user, tenant.id) do
                  {:ok, token, _claims} ->
                    {:noreply,
                     socket
                     |> put_flash(:info, "Welcome to BrokenRecord PaaS! Your organization has been created.")
                     |> redirect(to: ~p"/dashboard?token=#{token}")}

                  {:error, reason} ->
                    form = to_form(params, as: :auth, errors: [base: "Registration completed but login failed"])
                    {:noreply,
                     socket
                     |> assign(:loading, false)
                     |> assign(:form, form)
                     |> put_flash(:error, "Registration completed but login failed: #{reason}")}
                end

              {:error, _reason} ->
                form = to_form(params, as: :auth, errors: [base: "Registration failed"])
                {:noreply,
                 socket
                 |> assign(:loading, false)
                 |> assign(:form, form)
                 |> put_flash(:error, "Registration failed. Please try again.")}
            end

          {:error, _reason} ->
            form = to_form(params, as: :auth, errors: [base: "Failed to create organization"])
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:form, form)
             |> put_flash(:error, "Failed to create organization. Please try again.")}
        end

      {:error, reason} ->
        # Preserve the form data on error
        form = to_form(params, as: :auth, errors: [base: reason])
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:form, form)
         |> put_flash(:error, reason)}
    end
  end

    # Handle registration with missing or empty fields
  defp handle_registration(params, socket) do
    IO.puts("=== REGISTRATION VALIDATION ===")
    IO.inspect(params, label: "Registration params")

    errors = []
    errors = if Map.get(params, "email", "") == "", do: [{:email, "is required"} | errors], else: errors
    errors = if Map.get(params, "password", "") == "", do: [{:password, "is required"} | errors], else: errors
    errors = if Map.get(params, "name", "") == "", do: [{:name, "is required"} | errors], else: errors
    errors = if Map.get(params, "organization", "") == "", do: [{:organization, "is required"} | errors], else: errors

    IO.inspect(errors, label: "Registration errors")

    form = to_form(params, as: :auth, errors: errors)
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:form, form)
     |> put_flash(:error, "Please fill out all required fields.")}
  end

  defp get_user_tenants(user_id) do
    Logger.debug("Looking up tenants for user_id: #{user_id}")

    # Use the existing list_user_tenants function which efficiently gets user's memberships
    user_tenants = Tenants.list_user_tenants(user_id)
    Logger.debug("Found #{length(user_tenants)} tenants for user #{user_id}: #{inspect(Enum.map(user_tenants, & &1.id))}")

    if length(user_tenants) == 0 do
      Logger.warning("No tenants found for user #{user_id}. Checking if user exists in any tenant memberships...")

      # Debug: Check all tenant members to see if there's a different user ID
      all_members = BrokenRecord.Storage.ETSManager.list_all_tenant_members()
      Logger.debug("Total tenant members in system: #{length(all_members)}")

      matching_members = Enum.filter(all_members, fn member ->
        member.user_id == user_id
      end)
      Logger.debug("Members matching user_id #{user_id}: #{inspect(matching_members)}")

      # Check if there are members with similar email (debugging duplicate accounts)
      case BrokenRecord.Accounts.get_user(user_id) do
        {:ok, user} ->
          Logger.debug("Current user email: #{user.email}")
          similar_users = BrokenRecord.Storage.ETSManager.list_all_users()
          |> Enum.filter(fn u -> u.email == user.email && u.id != user_id end)
          Logger.debug("Other users with same email: #{inspect(Enum.map(similar_users, & &1.id))}")
        _ ->
          Logger.warning("Could not load user details for #{user_id}")
      end
    end

    user_tenants
    |> Enum.map(fn tenant_with_membership ->
      %{
        tenant_id: tenant_with_membership.id,
        tenant_name: tenant_with_membership.name,
        tenant_role: tenant_with_membership.member_role,
        joined_at: tenant_with_membership.joined_at
      }
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <!-- Logo and Header -->
        <div>
          <div class="mx-auto h-12 w-auto flex items-center justify-center">
            <Logo.logo />
          </div>
          <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900">
            <%= if @mode == :login, do: "Sign in to your account", else: "Create your organization" %>
          </h2>
          <p class="mt-2 text-center text-sm text-gray-600">
            <%= if @mode == :login do %>
              Or
              <button type="button" phx-click="toggle_mode" class="font-medium text-brand hover:text-brand-dark">
                create a new organization
              </button>
            <% else %>
              Already have an account?
              <button type="button" phx-click="toggle_mode" class="font-medium text-brand hover:text-brand-dark">
                Sign in instead
              </button>
            <% end %>
          </p>
        </div>

        <%= if @current_user && length(@user_tenants) > 0 do %>
          <!-- Tenant Selection -->
          <div class="bg-white shadow rounded-lg p-6">
            <h3 class="text-lg font-medium text-gray-900 mb-4">Select Organization</h3>
            <div class="space-y-3">
              <%= for tenant <- @user_tenants do %>
                <button
                  type="button"
                  phx-click="select_tenant"
                  phx-value-tenant_id={tenant.tenant_id}
                  class="w-full text-left p-4 border border-gray-200 rounded-lg hover:border-brand hover:bg-brand/5 transition-colors"
                >
                  <div class="flex items-center justify-between">
                    <div>
                      <h4 class="font-medium text-gray-900"><%= tenant.tenant_name %></h4>
                      <p class="text-sm text-gray-500">Role: <%= tenant.tenant_role %></p>
                    </div>
                    <svg class="h-5 w-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                    </svg>
                  </div>
                </button>
              <% end %>
            </div>
          </div>
        <% else %>
          <!-- Authentication Form -->
          <.form for={@form} phx-change="validate" phx-submit="submit" phx-trigger-action={false} class="mt-8 space-y-6">
            <!-- Display form errors -->
            <%= if @form.errors != [] do %>
              <div class="bg-red-50 border border-red-200 rounded-md p-4">
                <div class="flex">
                  <div class="flex-shrink-0">
                    <svg class="h-5 w-5 text-red-400" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"></path>
                    </svg>
                  </div>
                  <div class="ml-3">
                    <h3 class="text-sm font-medium text-red-800">Please fix the following errors:</h3>
                    <div class="mt-2 text-sm text-red-700">
                      <ul class="list-disc list-inside">
                        <%= for {field, error} <- @form.errors do %>
                          <li>
                            <strong><%= Phoenix.Naming.humanize(field) %>:</strong>
                            <%= case error do %>
                              <% {msg, _opts} -> %>
                                <%= msg %>
                              <% msg when is_binary(msg) -> %>
                                <%= msg %>
                              <% _ -> %>
                                <%= inspect(error) %>
                            <% end %>
                          </li>
                        <% end %>
                      </ul>
                      <!-- Debug output -->
                      <div class="mt-2 text-xs text-gray-500">
                        Debug: Form errors = <%= inspect(@form.errors) %>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
            <div class="rounded-md shadow-sm -space-y-px">
              <%= if @mode == :register do %>
                <div>
                  <label for="name" class="sr-only">Full name</label>
                  <input
                    type="text"
                    name="auth[name]"
                    id="name"
                    value={Phoenix.HTML.Form.input_value(@form, :name)}
                    autocomplete="name"
                    required
                    class="relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-t-md focus:outline-none focus:ring-brand focus:border-brand focus:z-10 sm:text-sm"
                    placeholder="Full name"
                  />
                </div>
                <div>
                  <label for="organization" class="sr-only">Organization name</label>
                  <input
                    type="text"
                    name="auth[organization]"
                    id="organization"
                    value={Phoenix.HTML.Form.input_value(@form, :organization)}
                    required
                    class="relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 focus:outline-none focus:ring-brand focus:border-brand focus:z-10 sm:text-sm"
                    placeholder="Organization name"
                  />
                </div>
              <% end %>

              <div>
                <label for="email" class="sr-only">Email address</label>
                <input
                  type="email"
                  name="auth[email]"
                  id="email"
                  value={Phoenix.HTML.Form.input_value(@form, :email)}
                  autocomplete="email"
                  required
                  class={"relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 focus:outline-none focus:ring-brand focus:border-brand focus:z-10 sm:text-sm #{if @mode == :register, do: "", else: "rounded-t-md"}"}
                  placeholder="Email address"
                />
              </div>

              <div>
                <label for="password" class="sr-only">Password</label>
                <input
                  type="password"
                  name="auth[password]"
                  id="password"
                  value={Phoenix.HTML.Form.input_value(@form, :password)}
                  autocomplete={if @mode == :login, do: "current-password", else: "new-password"}
                  required
                  class="relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-b-md focus:outline-none focus:ring-brand focus:border-brand focus:z-10 sm:text-sm"
                  placeholder="Password"
                />
              </div>
            </div>

            <div>
              <button
                type="submit"
                disabled={@loading}
                class="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-brand hover:bg-brand-dark focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <%= if @loading do %>
                  <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  <%= if @mode == :login, do: "Signing in...", else: "Creating organization..." %>
                <% else %>
                  <%= if @mode == :login, do: "Sign in", else: "Create organization" %>
                <% end %>
              </button>
            </div>
          </.form>
        <% end %>
      </div>
    </div>
    """
  end
end
