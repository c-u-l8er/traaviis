defmodule FSM.Reliability.CircuitBreakerTest do
  use ExUnit.Case, async: true

  test "closed -> open -> half_open -> closed" do
    fsm = FSM.Reliability.CircuitBreaker.new(%{})
    assert fsm.current_state == :closed
    {:ok, fsm} = FSM.Reliability.CircuitBreaker.navigate(fsm, :trip, %{})
    assert fsm.current_state == :open
    {:ok, fsm} = FSM.Reliability.CircuitBreaker.navigate(fsm, :cooldown, %{})
    assert fsm.current_state == :half_open
    {:ok, fsm} = FSM.Reliability.CircuitBreaker.navigate(fsm, :probe_success, %{})
    assert fsm.current_state == :closed
  end
end


