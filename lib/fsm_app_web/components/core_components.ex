defmodule FSMAppWeb.CoreComponents do
  @moduledoc """
  Provides core UI components that are commonly used across the application.
  """
  use Phoenix.Component

  # Import logo component globally
  alias FSMAppWeb.Components.Logo

  @doc """
  Renders the FSMApp logo.
  Delegates to the Logo component for consistent branding.
  """
  defdelegate logo(assigns), to: Logo

  @doc """
  Renders logo with text for branding.
  Delegates to the Logo component for consistent branding.
  """
  defdelegate logo_with_text(assigns), to: Logo

  @doc """
  Renders a modern button component with consistent styling.
  """
  attr :type, :string, default: "button"
  attr :class, :string, default: ""
  attr :variant, :string, default: "primary", values: ~w(primary secondary danger)
  attr :loading, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :rest, :global, include: ~w(form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      {@rest}
      type={@type}
      disabled={@loading || @disabled}
      class={[
        "group relative inline-flex items-center justify-center rounded-md px-4 py-2 text-sm font-semibold shadow-sm transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 disabled:opacity-50 disabled:cursor-not-allowed",
        button_variant_class(@variant),
        @class
      ]}
    >
      <%= if @loading do %>
        <svg class="animate-spin -ml-1 mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
      <% end %>
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @doc """
  Renders an enhanced error message component similar to BrokenRecord pattern.
  """
  attr :title, :string, default: "Please fix the following errors:"
  attr :errors, :list, required: true
  attr :class, :string, default: ""

  def error_display(assigns) do
    ~H"""
    <%= if @errors != [] do %>
      <div class={["bg-red-50 border border-red-200 rounded-md p-4", @class]}>
        <div class="flex">
          <div class="flex-shrink-0">
            <svg class="h-5 w-5 text-red-400" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"></path>
            </svg>
          </div>
          <div class="ml-3">
            <h3 class="text-sm font-medium text-red-800"><%= @title %></h3>
            <div class="mt-2 text-sm text-red-700">
              <ul class="list-disc list-inside space-y-1">
                <%= for {field, error} <- @errors do %>
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
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  @doc """
  Renders a success message component.
  """
  attr :message, :string, required: true
  attr :class, :string, default: ""

  def success_display(assigns) do
    ~H"""
    <div class={["bg-green-50 border border-green-200 rounded-md p-4", @class]}>
      <div class="flex">
        <div class="flex-shrink-0">
          <svg class="h-5 w-5 text-green-400" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"></path>
          </svg>
        </div>
        <div class="ml-3">
          <p class="text-sm text-green-700">
            <%= @message %>
          </p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a loading spinner component.
  """
  attr :size, :string, default: "medium", values: ~w(small medium large)
  attr :class, :string, default: ""
  attr :text, :string, default: nil

  def loading_spinner(assigns) do
    assigns = assign(assigns, :spinner_class, spinner_size_class(assigns.size))

    ~H"""
    <div class={["flex items-center justify-center", @class]}>
      <svg class={["animate-spin text-indigo-600", @spinner_class]} fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
      <%= if @text do %>
        <span class="ml-2 text-sm text-gray-600"><%= @text %></span>
      <% end %>
    </div>
    """
  end

  # Private helper functions

  defp button_variant_class("primary"), do: "bg-indigo-600 text-white hover:bg-indigo-700 focus-visible:outline-indigo-600"
  defp button_variant_class("secondary"), do: "bg-gray-200 text-gray-900 hover:bg-gray-300 focus-visible:outline-gray-500"
  defp button_variant_class("danger"), do: "bg-red-600 text-white hover:bg-red-700 focus-visible:outline-red-600"

  defp spinner_size_class("small"), do: "h-4 w-4"
  defp spinner_size_class("medium"), do: "h-6 w-6"
  defp spinner_size_class("large"), do: "h-8 w-8"

  attr :for, :any, required: true
  attr :action, :string, required: true
  attr :method, :string, default: "post"
  slot :inner_block
  def simple_form(assigns) do
    ~H"""
    <form action={@action} method={@method} class="space-y-6">
      <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
      <%= render_slot(@inner_block) %>
    </form>
    """
  end

  attr :field, :atom, required: true
  attr :type, :string, default: "text"
  attr :label, :string, default: nil
  attr :required, :boolean, default: false
  def input(assigns) do
    ~H"""
    <div>
      <label :if={@label} class="block text-sm font-medium text-gray-700"><%= @label %></label>
      <input name={to_string(@field)} value={assigns[:value]} type={@type} required={@required} class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm" />
    </div>
    """
  end

  # Flash messages
  attr :flash, :map, default: %{}
  def flash_group(assigns) do
    ~H"""
    <div class="space-y-2">
      <%= for kind <- [:info, :error] do %>
        <%= if msg = @flash[kind] do %>
          <.flash kind={kind} message={msg} />
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :kind, :atom, values: [:info, :error]
  attr :message, :string, required: true
  def flash(assigns) do
    ~H"""
    <div class={[
      "rounded p-3 text-sm",
      @kind == :info && "bg-green-50 text-green-800 border border-green-200",
      @kind == :error && "bg-red-50 text-red-800 border border-red-200"
    ]}>
      <%= @message %>
    </div>
    """
  end

  # Changeset error rendering
  attr :changeset, :any, required: true
  attr :field, :atom, required: true
  def error_tag(assigns) do
    ~H"""
    <%= if @changeset && @changeset.action do %>
      <%= for msg <- error_messages(@changeset, @field) do %>
        <div class="text-sm text-red-600"><%= msg %></div>
      <% end %>
    <% end %>
    """
  end

  defp error_messages(%{errors: errors}, field) do
    errors
    |> Keyword.get_values(field)
    |> Enum.map(fn {msg, opts} -> Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{" <> to_string(k) <> "}", to_string(v)) end) end)
  end
end
