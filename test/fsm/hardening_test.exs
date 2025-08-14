defmodule FSM.HardeningTest do
  use ExUnit.Case, async: false

  @moduletag :hardening

  defmodule TestFSM do
    use FSM.Navigator

    initial_state :idle

    state :idle do
      navigate_to :active, when: :start
    end

    state :active do
      navigate_to :idle, when: :stop
    end

    def handle_external_event(fsm, _src, event_type, event_data) do
      if pid = Process.whereis(:fsm_test_proc) do
        send(pid, {:external_event, event_type, event_data})
      end
      fsm
    end

    def handle_broadcast_event(_fsm, event_type, event_data) do
      if pid = Process.whereis(:fsm_test_proc) do
        send(pid, {:broadcast_event, event_type, event_data})
      end
      :ok
    end
  end

  defmodule TestRaiserFSM do
    use FSM.Navigator

    initial_state :idle

    state :idle do
      navigate_to :active, when: :start
    end

    state :active do
      navigate_to :idle, when: :stop
    end

    def handle_external_event(fsm, _src, _event_type, event_data) do
      if event_data[:raise] do
        raise "boom"
      end
      fsm
    end
  end

  setup do
    # Register the test process so helper FSM modules can find us
    Process.register(self(), :fsm_test_proc)

    on_exit(fn ->
      if Process.whereis(:fsm_test_proc), do: Process.unregister(:fsm_test_proc)
    end)

    :ok
  end

  test "emits telemetry for transitions and event appends" do
    handler_id = "telemetry-hardening-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    parent = self()
    :ok = :telemetry.attach_many(handler_id,
      [
        [:fsm, :transition],
        [:fsm, :event_store, :append]
      ],
      fn event, measurements, metadata, _cfg ->
        send(parent, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    # Create and drive an FSM to trigger both created and transition appends
    {:ok, fsm_id} = FSM.Manager.create_fsm(TestFSM, %{}, "t-telemetry")
    {:ok, _} = FSM.Manager.send_event(fsm_id, :start, %{})

    # Expect at least one event_store append (created) and one transition telemetry
    assert_receive {:telemetry, [:fsm, :event_store, :append], _m, %{type: "created", fsm_id: _}}, 500
    assert_receive {:telemetry, [:fsm, :transition], %{duration_us: _}, %{from: :idle, to: :active, event: :start}}, 500

    # And a second event_store append for the transition record
    assert_receive {:telemetry, [:fsm, :event_store, :append], _m, %{type: "transition", fsm_id: _}}, 500
  end

  test "broadcast emits telemetry and invokes handlers via supervised tasks" do
    handler_id = "telemetry-broadcast-" <> Integer.to_string(:erlang.unique_integer([:positive]))
    parent = self()
    :ok = :telemetry.attach(handler_id, [:fsm, :broadcast], fn event, measurements, metadata, _ ->
      send(parent, {:telemetry, event, measurements, metadata})
    end, nil)
    on_exit(fn -> :telemetry.detach(handler_id) end)

    # Ensure at least one FSM exists in the tenant to receive the broadcast
    _ = FSM.Manager.create_fsm(TestFSM, %{}, "t-broadcast")

    # Fire a broadcast and assert both telemetry and callback side effect
    :ok = FSM.Registry.broadcast(:system_notice, %{note: "hi"}, "t-broadcast")

    assert_receive {:telemetry, [:fsm, :broadcast], %{count: c}, %{event_type: :system_notice, tenant_id: "t-broadcast"}} when is_integer(c) and c >= 1, 500
    assert_receive {:broadcast_event, :system_notice, %{note: "hi"}}, 500
  end

  test "subscriber callbacks are isolated (errors do not break transition)" do
    # Create source and two subscribers (one normal, one that raises)
    {:ok, src_id} = FSM.Manager.create_fsm(TestFSM, %{}, "t-sub")
    {:ok, ok_id} = FSM.Manager.create_fsm(TestFSM, %{}, "t-sub")
    {:ok, bad_id} = FSM.Manager.create_fsm(TestRaiserFSM, %{}, "t-sub")

    # Subscribe both to the source
    {:ok, {_mod, src}} = FSM.Registry.get(src_id)
    src = TestFSM.subscribe(src, ok_id)
    src = TestFSM.subscribe(src, bad_id)
    :ok = FSM.Registry.update(src_id, src)

    # Drive a state change; the bad subscriber will raise, but Manager should still succeed
    {:ok, _} = FSM.Manager.send_event(src_id, :start, %{raise: true})

    # We still get the callback from the non-raising subscriber
    assert_receive {:external_event, :state_changed, %{event: :start}}, 500
  end
end
