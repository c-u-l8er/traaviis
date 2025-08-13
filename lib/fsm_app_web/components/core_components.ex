defmodule FSMAppWeb.CoreComponents do
  @moduledoc """
  Provides core UI components that are commonly used across the application.
  """
  use Phoenix.Component

  # You can add your own components here
  # For example:
  attr :type, :string, default: "button"
  attr :class, :string, default: ""
  attr :rest, :global
  slot :inner_block, required: true
  def button(assigns) do
    ~H"""
    <button {@rest} type={@type} class={["inline-flex items-center justify-center rounded-md bg-indigo-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600", @class]}>
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

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
