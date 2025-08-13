defmodule FSM.Safety.ApprovalGateTest do
  use ExUnit.Case, async: true

  test "pending -> approved" do
    fsm = FSM.Safety.ApprovalGate.new(%{})
    assert fsm.current_state == :pending
    {:ok, fsm} = FSM.Safety.ApprovalGate.navigate(fsm, :approve, %{})
    assert fsm.current_state == :approved
  end
end


