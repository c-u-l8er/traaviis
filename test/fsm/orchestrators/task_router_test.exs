defmodule FSM.Orchestrators.TaskRouterTest do
  use ExUnit.Case, async: true

  test "classify -> route -> handoff -> acked" do
    fsm = FSM.Orchestrators.TaskRouter.new(%{})
    assert fsm.current_state == :classify

    {:ok, fsm} = FSM.Orchestrators.TaskRouter.navigate(fsm, :classified, %{})
    {:ok, fsm} = FSM.Orchestrators.TaskRouter.navigate(fsm, :routed, %{})
    {:ok, fsm} = FSM.Orchestrators.TaskRouter.navigate(fsm, :ack, %{})
    assert fsm.current_state == :acked
  end
end


