defmodule FSMApp.MCP.GetAvailableFSMModulesTest do
  use ExUnit.Case, async: true

  test "returns discovered FSM modules" do
    modules = FSM.ModuleDiscovery.list_available_fsms()
    assert is_list(modules)
    assert Enum.any?(modules, fn m -> m.module == FSM.SmartDoor end)
  end
end


