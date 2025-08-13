defmodule FSM.Integration.ApiCall do
  @moduledoc """
  External API call with OAuth refresh and error mapping.
  """
  use FSM.Navigator

  state :ready do
    navigate_to :calling, when: :call
  end

  state :calling do
    navigate_to :done, when: :success
    navigate_to :refresh_token, when: :unauthorized
    navigate_to :failed, when: :error
  end

  state :refresh_token do
    navigate_to :calling, when: :refreshed
    navigate_to :failed, when: :refresh_failed
  end

  state :done do
  end

  state :failed do
  end

  initial_state :ready
end
