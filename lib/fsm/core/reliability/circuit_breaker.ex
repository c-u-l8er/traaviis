defmodule FSM.Reliability.CircuitBreaker do
  @moduledoc """
  Circuit breaker with open/half-open/closed states.
  """
  use FSM.Navigator

  state :closed do
    navigate_to :open, when: :trip
  end

  state :open do
    navigate_to :half_open, when: :cooldown
  end

  state :half_open do
    navigate_to :closed, when: :probe_success
    navigate_to :open, when: :probe_failure
  end

  initial_state :closed
end
