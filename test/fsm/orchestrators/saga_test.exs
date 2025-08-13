defmodule FSM.Orchestrators.SagaTest do
  use ExUnit.Case, async: true

  test "basic saga path" do
    fsm = FSM.Orchestrators.Saga.new(%{})
    assert fsm.current_state == :planning

    {:ok, fsm} = FSM.Orchestrators.Saga.navigate(fsm, :start, %{})
    assert fsm.current_state == :running

    {:ok, fsm} = FSM.Orchestrators.Saga.navigate(fsm, :all_steps_done, %{})
    assert fsm.current_state == :completed
  end
end


