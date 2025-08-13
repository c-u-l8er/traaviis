defmodule FSM.Orchestrators.PlanExecute do
  @moduledoc """
  Deterministic plan-execute-observe-evaluate loop for agent runs.
  """
  use FSM.Navigator

  state :plan do
    navigate_to :execute, when: :submit_plan
    navigate_to :aborted, when: :abort
  end

  state :execute do
    navigate_to :observe, when: :tool_result
    navigate_to :aborted, when: :abort
  end

  state :observe do
    navigate_to :evaluate, when: :observation_ready
  end

  state :evaluate do
    navigate_to :plan, when: :replan
    navigate_to :done, when: :finalize
    navigate_to :aborted, when: :abort
  end

  state :done do
  end

  state :aborted do
  end

  initial_state :plan
end
