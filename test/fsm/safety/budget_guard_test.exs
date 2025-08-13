defmodule FSM.Safety.BudgetGuardTest do
  use ExUnit.Case, async: true

  test "green -> warn -> blocked -> green" do
    fsm = FSM.Safety.BudgetGuard.new(%{})
    assert fsm.current_state == :green
    {:ok, fsm} = FSM.Safety.BudgetGuard.navigate(fsm, :threshold_reached, %{})
    assert fsm.current_state == :warn
    {:ok, fsm} = FSM.Safety.BudgetGuard.navigate(fsm, :exceeded, %{})
    assert fsm.current_state == :blocked
    {:ok, fsm} = FSM.Safety.BudgetGuard.navigate(fsm, :reset, %{})
    assert fsm.current_state == :green
  end
end


