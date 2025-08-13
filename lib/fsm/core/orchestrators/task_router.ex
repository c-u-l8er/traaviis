defmodule FSM.Orchestrators.TaskRouter do
  @moduledoc """
  Routes tasks to tools/agents based on policy and retrieval.
  """
  use FSM.Navigator

  state :classify do
    navigate_to :route, when: :classified
    navigate_to :timeout, when: :timeout
  end

  state :route do
    navigate_to :handoff, when: :routed
    navigate_to :timeout, when: :timeout
  end

  state :handoff do
    navigate_to :acked, when: :ack
    navigate_to :timeout, when: :timeout
  end

  state :acked do
  end

  state :timeout do
  end

  initial_state :classify
end
