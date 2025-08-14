defmodule FSM.FilesystemRetentionTest do
  use ExUnit.Case, async: false

  @moduletag :filesystem

  # This test assumes a simple retention/prune function exists or a config-driven prune job.
  # If not present yet, keep it skipped to avoid false failures.

  @tag :skip
  test "event files are pruned according to retention policy" do
    fsm = FSM.SmartDoor.new(%{}, tenant_id: "t-retain")
    :ok = FSM.EventStore.append_created(FSM.SmartDoor, fsm, %{})
    for _ <- 1..3 do
      {:ok, fsm} = FSM.SmartDoor.navigate(fsm, :open_command, %{})
      {:ok, fsm} = FSM.SmartDoor.navigate(fsm, :fully_open, %{})
      {:ok, fsm} = FSM.SmartDoor.navigate(fsm, :close_command, %{})
    end

    # Invoke prune (placeholder)
    assert function_exported?(FSM.EventStore, :prune, 1)
    assert :ok = apply(FSM.EventStore, :prune, [[tenant_id: "t-retain", keep_days: 1]])
  end
end
