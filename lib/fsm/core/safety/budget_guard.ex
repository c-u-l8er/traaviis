defmodule FSM.Safety.BudgetGuard do
  @moduledoc """
  Enforces budgets/quotas for tokens, spend, and calls per tenant/tool.
  """
  use FSM.Navigator

  state :green do
    navigate_to :warn, when: :threshold_reached
    navigate_to :blocked, when: :exceeded
    navigate_to :green, when: :reset
  end

  state :warn do
    navigate_to :blocked, when: :exceeded
    navigate_to :green, when: :reset
  end

  state :blocked do
    navigate_to :green, when: :reset
  end

  initial_state :green
end
