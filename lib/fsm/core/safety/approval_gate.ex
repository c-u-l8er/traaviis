defmodule FSM.Safety.ApprovalGate do
  @moduledoc """
  Human-in-the-loop approval checkpoint with optional escalation.
  """
  use FSM.Navigator

  state :pending do
    navigate_to :approved, when: :approve
    navigate_to :denied, when: :deny
    navigate_to :escalated, when: :escalate
    navigate_to :expired, when: :expire
  end

  state :approved do
  end

  state :denied do
  end

  state :escalated do
  end

  state :expired do
  end

  initial_state :pending
end
