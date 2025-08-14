defmodule FSM.EventStoreTest do
  use ExUnit.Case, async: true

  test "append and list events" do
    fsm = FSM.SmartDoor.new(%{location: "test"}, tenant_id: "t1")
    :ok = FSM.EventStore.append_created(FSM.SmartDoor, fsm, %{location: "test"})
    {:ok, fsm} = FSM.SmartDoor.navigate(fsm, :open_command, %{})
    {:ok, fsm} = FSM.SmartDoor.navigate(fsm, :fully_open, %{})
    # Allow async file IO flush
    Process.sleep(10)
    {:ok, events} = FSM.EventStore.list(fsm.id)
    assert Enum.any?(events, fn ev -> ev["type"] == "transition" end)
  end
end
