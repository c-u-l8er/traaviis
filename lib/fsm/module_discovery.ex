defmodule FSM.ModuleDiscovery do
  @moduledoc """
  Discover FSM modules dynamically.

  This inspects the current application modules and returns the list of
  modules that look like instantiable FSMs (i.e., defined under `FSM.*` and
  exporting the `new/2` and `navigate/3` functions provided by `FSM.Navigator`).
  """

  @app :fsm_app

  @doc """
  List available FSM modules for creation in the UI.

  Returns a list of maps with keys: `:name`, `:description`, `:module`.
  The `:name` is the short module name (e.g., "SmartDoor").
  """
  def list_available_fsms do
    modules = Application.spec(@app, :modules) || []

    modules
    |> Enum.filter(&is_fsm_module?/1)
    |> Enum.map(&describe_module/1)
    |> Enum.sort_by(& &1.name)
  end

  defp is_fsm_module?(module) when is_atom(module) do
    case Atom.to_string(module) do
      "Elixir.FSM." <> rest ->
        not excluded_namespace?(rest) and
          function_exported?(module, :new, 2) and
          function_exported?(module, :navigate, 3)

      _ ->
        false
    end
  end

  defp excluded_namespace?(rest) do
    String.starts_with?(rest, "Components.") or
      String.starts_with?(rest, "Plugins.") or
      rest in ["Registry", "Manager", "Navigator", "ModuleDiscovery"]
  end

  defp describe_module(module) do
    states = if function_exported?(module, :states, 0), do: module.states(), else: []
    components =
      if function_exported?(module, :components, 0) do
        module.components() |> Enum.map(&short_name/1)
      else
        []
      end

    %{
      name: module |> Module.split() |> List.last(),
      description: fetch_moduledoc(module),
      module: module,
      states: Enum.map(states, &to_string/1),
      components: components
    }
  end

  defp short_name(mod) when is_atom(mod) do
    mod |> Module.split() |> List.last()
  end

  defp fetch_moduledoc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} when is_binary(doc) ->
        doc

      {:docs_v1, _, _, _, doc, _, _} when is_binary(doc) ->
        doc

      _ ->
        ""
    end
  end
end
