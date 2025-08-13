defmodule FSM.Orchestrators.PlanExecuteTest do
  use ExUnit.Case, async: true

  test "plan -> execute -> observe -> evaluate -> done" do
    fsm = FSM.Orchestrators.PlanExecute.new(%{})
    assert fsm.current_state == :plan

    {:ok, fsm} = FSM.Orchestrators.PlanExecute.navigate(fsm, :submit_plan, %{})
    {:ok, fsm} = FSM.Orchestrators.PlanExecute.navigate(fsm, :tool_result, %{})
    {:ok, fsm} = FSM.Orchestrators.PlanExecute.navigate(fsm, :observation_ready, %{})
    {:ok, fsm} = FSM.Orchestrators.PlanExecute.navigate(fsm, :finalize, %{})
    assert fsm.current_state == :done
  end
end


