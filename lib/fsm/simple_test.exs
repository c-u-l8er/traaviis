defmodule FSM.SimpleTest do
  use ExUnit.Case
  alias FSM.SmartDoor

  test "SmartDoor module compiles successfully" do
    # This test just verifies that the module compiles
    assert is_atom(SmartDoor)
    assert function_exported?(SmartDoor, :new, 2)
  end

  test "SmartDoor has expected states" do
    # Test that the FSM has the expected states
    fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")
    assert fsm.current_state == :closed
  end
end
