defmodule FSM.Components.TimerTest do
  use ExUnit.Case
  alias FSM.Components.Timer

  describe "Timer Component" do
    test "has correct states" do
      states = Timer.states()
      assert :idle in states
      assert :running in states
      assert :paused in states
      assert :expired in states
      assert length(states) == 4
    end

    test "has correct transitions" do
      transitions = Timer.transitions()

      # Check idle transitions
      assert {:idle, :start, :running, []} in transitions

      # Check running transitions
      assert {:running, :stop, :idle, []} in transitions
      assert {:running, :pause, :paused, []} in transitions
      assert {:running, :timeout, :expired, []} in transitions

      # Check paused transitions
      assert {:paused, :resume, :running, []} in transitions
      assert {:paused, :stop, :idle, []} in transitions

      # Check expired transitions
      assert {:expired, :reset, :idle, []} in transitions

      assert length(transitions) == 7
    end

    test "creates timer data structure" do
      timer_data = Timer.start_timer(:test_timer, 5000)

      assert is_map(timer_data)
      assert timer_data.timer_name == :test_timer
      assert timer_data.duration == 5000
      assert timer_data.start_time != nil
      assert timer_data.remaining_time == 5000
      assert is_reference(timer_data.timer_ref)
      assert timer_data.callback == nil
    end

    test "stops timer correctly" do
      timer_data = Timer.start_timer(:test_timer, 5000)
      assert :ok = Timer.stop_timer(timer_data.timer_ref)
    end

    test "handles stopping non-existent timer gracefully" do
      assert :ok = Timer.stop_timer(nil)
      assert :ok = Timer.stop_timer("invalid")
    end

    test "checks timer expiration correctly" do
      # Create a timer that expires immediately
      timer_data = %{
        timer_name: :test,
        duration: 0,
        start_time: System.monotonic_time(:millisecond) - 1000,
        remaining_time: 0,
        timer_ref: nil,
        callback: nil
      }

      assert Timer.timer_expired?(timer_data) == true

      # Create a timer that hasn't expired
      non_expired_timer = %{
        timer_name: :test,
        duration: 10000,
        start_time: System.monotonic_time(:millisecond),
        remaining_time: 10000,
        timer_ref: nil,
        callback: nil
      }

      assert Timer.timer_expired?(non_expired_timer) == false
    end

    test "handles invalid timer data gracefully" do
      assert Timer.timer_expired?(nil) == false
      assert Timer.timer_expired?(%{}) == false
    end

    test "resets timer" do
      assert :ok = Timer.reset_timer(:test_timer)
    end
  end

  describe "Timer Component FSM functionality" do
    test "creates FSM instance" do
      fsm = Timer.new()
      assert fsm.current_state == :idle
    end

    test "transitions from idle to running" do
      fsm = Timer.new()
      {:ok, new_fsm} = Timer.navigate(fsm, :start)
      assert new_fsm.current_state == :running
    end

    test "transitions from running to paused" do
      fsm = Timer.new()
      {:ok, running_fsm} = Timer.navigate(fsm, :start)
      {:ok, paused_fsm} = Timer.navigate(running_fsm, :pause)
      assert paused_fsm.current_state == :paused
    end

    test "transitions from running to expired" do
      fsm = Timer.new()
      {:ok, running_fsm} = Timer.navigate(fsm, :start)
      {:ok, expired_fsm} = Timer.navigate(running_fsm, :timeout)
      assert expired_fsm.current_state == :expired
    end

    test "transitions from expired to idle" do
      fsm = Timer.new()
      {:ok, running_fsm} = Timer.navigate(fsm, :start)
      {:ok, expired_fsm} = Timer.navigate(running_fsm, :timeout)
      {:ok, idle_fsm} = Timer.navigate(expired_fsm, :reset)
      assert idle_fsm.current_state == :idle
    end

    test "handles invalid transitions gracefully" do
      fsm = Timer.new()

      # Try to pause from idle (invalid)
      {:error, :invalid_transition} = Timer.navigate(fsm, :pause)

      # Try to resume from idle (invalid)
      {:error, :invalid_transition} = Timer.navigate(fsm, :resume)

      # Try to timeout from idle (invalid)
      {:error, :invalid_transition} = Timer.navigate(fsm, :timeout)

      # Try to reset from idle (invalid)
      {:error, :invalid_transition} = Timer.navigate(fsm, :reset)
    end
  end
end
