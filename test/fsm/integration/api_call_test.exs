defmodule FSM.Integration.ApiCallTest do
  use ExUnit.Case, async: true

  test "ready -> calling -> refresh_token -> calling -> done" do
    fsm = FSM.Integration.ApiCall.new(%{})
    assert fsm.current_state == :ready
    {:ok, fsm} = FSM.Integration.ApiCall.navigate(fsm, :call, %{})
    assert fsm.current_state == :calling
    {:ok, fsm} = FSM.Integration.ApiCall.navigate(fsm, :unauthorized, %{})
    assert fsm.current_state == :refresh_token
    {:ok, fsm} = FSM.Integration.ApiCall.navigate(fsm, :refreshed, %{})
    assert fsm.current_state == :calling
    {:ok, fsm} = FSM.Integration.ApiCall.navigate(fsm, :success, %{})
    assert fsm.current_state == :done
  end
end


