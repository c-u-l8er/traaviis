defmodule FSMAppWeb.Components.Logo do
  @moduledoc """
  Logo component for consistent branding across the application.

  Provides the FSMApp logo in various sizes and styles, similar to BrokenRecord's approach.
  """
  use Phoenix.Component

  @doc """
  Renders the FSMApp logo.

  ## Examples

      <Logo.logo />
      <Logo.logo class="h-8 w-auto" />
      <Logo.logo size="large" />
  """
  attr :class, :string, default: "h-12 w-auto"
  attr :size, :string, default: "medium", values: ~w(small medium large)
  attr :alt, :string, default: "FSMApp"

  def logo(assigns) do
    assigns = assign(assigns, :final_class, logo_class(assigns.size, assigns.class))

    ~H"""
    <img
      src="/images/logo.png"
      alt={@alt}
      class={@final_class}
    />
    """
  end

  @doc """
  Renders logo with text for branding.
  """
  attr :class, :string, default: "h-12 w-auto"
  attr :text_class, :string, default: "ml-3 text-2xl font-bold text-gray-900"
  attr :size, :string, default: "medium", values: ~w(small medium large)

  def logo_with_text(assigns) do
    assigns = assign(assigns, :final_class, logo_class(assigns.size, assigns.class))

    ~H"""
    <div class="flex items-center">
      <img
        src="/images/logo.png"
        alt="FSMApp"
        class={@final_class}
      />
      <span class={@text_class}>FSMApp</span>
    </div>
    """
  end

  # Private helper functions

  defp logo_class("small", custom_class), do: merge_classes("h-8 w-auto", custom_class)
  defp logo_class("medium", custom_class), do: merge_classes("h-12 w-auto", custom_class)
  defp logo_class("large", custom_class), do: merge_classes("h-16 w-auto", custom_class)
  defp logo_class(_, custom_class), do: merge_classes("h-12 w-auto", custom_class)

  defp merge_classes(default, nil), do: default
  defp merge_classes(default, ""), do: default
  defp merge_classes(_default, custom), do: custom
end
