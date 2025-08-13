defmodule FSM.Orchestrators.Saga do
  @moduledoc """
  Saga orchestrator for multi-step workflows with compensation.
  """
  use FSM.Navigator

  state :planning do
    navigate_to :running, when: :start
    navigate_to :failed, when: :invalid_plan
  end

  state :running do
    navigate_to :compensating, when: :step_failed
    navigate_to :completed, when: :all_steps_done
  end

  state :compensating do
    navigate_to :failed, when: :compensation_exhausted
    navigate_to :completed, when: :compensation_done
  end

  state :completed do
  end

  state :failed do
  end

  initial_state :planning
end
