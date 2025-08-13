defmodule FSM.ModuleDiscoveryTest do
  use ExUnit.Case, async: true

  test "lists FSM.* modules that export new/2 and navigate/3" do
    mods = FSM.ModuleDiscovery.list_available_fsms()
    assert Enum.all?(mods, fn m -> function_exported?(m.module, :new, 2) and function_exported?(m.module, :navigate, 3) end)
  end
end


