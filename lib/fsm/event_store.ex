defmodule FSM.EventStore do
  @moduledoc """
  Append-only event store for FSM transitions and lifecycle events.

  Stores JSON Lines (JSONL) under ./data/events/<fsm_id>.jsonl
  """
  require Logger

  @spec append_transition(module(), struct(), atom(), atom(), map()) :: :ok | {:error, term()}
  def append_transition(fsm_module, fsm, from_state, event, event_data) do
    record = %{
      type: "transition",
      fsm_id: id_to_string(fsm.id),
      tenant_id: fsm.tenant_id,
      module: Atom.to_string(fsm_module),
      from: to_string(from_state),
      to: to_string(fsm.current_state),
      event: to_string(event),
      event_data: sanitize(event_data || %{}),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      seq: System.unique_integer([:monotonic, :positive])
    }
    append_record(record)
  end

  @spec append_created(module(), struct(), map()) :: :ok | {:error, term()}
  def append_created(fsm_module, fsm, initial_data) do
    record = %{
      type: "created",
      fsm_id: id_to_string(fsm.id),
      tenant_id: fsm.tenant_id,
      module: Atom.to_string(fsm_module),
      initial_state: to_string(fsm.current_state),
      initial_data: sanitize(initial_data || %{}),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      seq: System.unique_integer([:monotonic, :positive])
    }

    append_record(record)
  end

  @spec list(term()) :: {:ok, [map()]}
  def list(fsm_id) do
    key = id_to_string(fsm_id)
    file_events = list_events_from_fs(key)

    cache_events =
      if :ets.whereis(:fsm_event_store_cache) != :undefined do
        :ets.lookup(:fsm_event_store_cache, key)
        |> Enum.map(fn {_k, rec} -> rec end)
      else
        []
      end

    merged = (file_events ++ cache_events)
    |> Enum.map(&normalize_event_keys/1)
    |> Enum.uniq_by(& &1["seq"])
    |> Enum.sort_by(& &1["seq"])

    {:ok, merged}
  end

  defp data_dir, do: Path.expand("data")
  defp events_root(tenant), do: Path.join(data_dir(), Path.join([tenant || "no_tenant", "events"]))

  defp append_record(record) do
    with start <- System.monotonic_time(:microsecond),
         {:ok, json} <- Jason.encode(record),
         path <- event_file_path(record),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, json <> "\n", [:append]) do
      :telemetry.execute([
        :fsm, :event_store, :append
      ], %{duration_us: System.monotonic_time(:microsecond) - start}, %{path: path, module: record.module, fsm_id: record.fsm_id, type: record.type})
      ensure_cache_table()
      true = :ets.insert(:fsm_event_store_cache, {record.fsm_id, record})
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to append event: #{inspect(reason)}")
        {:error, reason}
      other ->
        Logger.error("Unexpected error appending event: #{inspect(other)}")
        {:error, other}
    end
  end

  defp sanitize(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {to_string(k), sanitize(v)} end)
    |> Enum.into(%{})
  end
  defp sanitize(value) when is_list(value), do: Enum.map(value, &sanitize/1)
  defp sanitize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp sanitize(v) when is_atom(v), do: Atom.to_string(v)
  defp sanitize(v), do: v

  defp id_to_string(ref) when is_reference(ref), do: inspect(ref)
  defp id_to_string(bin) when is_binary(bin), do: bin
  defp id_to_string(other), do: inspect(other)

  defp ensure_cache_table do
    case :ets.whereis(:fsm_event_store_cache) do
      :undefined ->
        try do
          :ets.new(:fsm_event_store_cache, [
            :named_table,
            :bag,
            :public,
            read_concurrency: true,
            write_concurrency: true
          ])
        rescue
          ArgumentError -> :ok
        end
      _ -> :ok
    end
  end

  defp normalize_event_keys(event) when is_map(event) do
    event
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.into(%{})
  end

  # Partitioned path helpers
  defp event_file_path(%{tenant_id: tenant_id, module: module_str, fsm_id: fsm_id, timestamp: iso}) do
    dt = case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
    tenant = tenant_id || "no_tenant"
    mod_short = module_short(module_str)
    fsm_safe = sanitize_for_path(fsm_id)
    Path.join([
      events_root(tenant), mod_short, fsm_safe,
      to_string(dt.year), pad2(dt.month), pad2(dt.day) <> ".jsonl"
    ])
  end

  defp list_events_from_fs(fsm_id_str) do
    safe = sanitize_for_path(fsm_id_str)
    # Search under all tenants' events roots
    pattern = Path.join([data_dir(), "**", "events", "**", safe, "**", "*.jsonl"])
    legacy = Path.join(Path.join(data_dir(), "events"), safe <> ".jsonl")
    files = (Path.wildcard(pattern, match_dot: true) ++ (if File.exists?(legacy), do: [legacy], else: []))
    Logger.info("EventStore.list_events_from_fs: fsm_id=#{fsm_id_str}, safe=#{safe}")
    Logger.info("EventStore.list_events_from_fs: pattern=#{pattern}")
    Logger.info("EventStore.list_events_from_fs: found files=#{inspect(files)}")

    events = files
    |> Enum.flat_map(fn path ->
      Logger.info("EventStore.list_events_from_fs: processing file #{path}")
      try do
                file_events = path
        |> File.stream!([], :line)
        |> Enum.reduce([], fn line, acc ->
          # Trim whitespace and skip empty lines
          trimmed_line = String.trim(line)
          if trimmed_line != "" do
            case Jason.decode(trimmed_line) do
              {:ok, map} -> [map | acc]
              {:error, reason} ->
                Logger.warn("EventStore.list_events_from_fs: failed to decode line in #{path}: #{inspect(reason)}")
                Logger.warn("EventStore.list_events_from_fs: problematic line: #{inspect(trimmed_line)}")
                acc
            end
          else
            acc
          end
        end)
        |> Enum.reverse()
        Logger.info("EventStore.list_events_from_fs: file #{path} yielded #{length(file_events)} events")
        file_events
      rescue
        e ->
          Logger.error("EventStore.list_events_from_fs: error processing #{path}: #{inspect(e)}")
          []
      end
    end)
    Logger.info("EventStore.list_events_from_fs: total events found: #{length(events)}")
    events
  end

  defp module_short("Elixir." <> rest), do: module_short(rest)
  defp module_short(mod) when is_binary(mod) do
    mod |> String.split(".") |> List.last()
  end

  defp sanitize_for_path(str) do
    str
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_\-]+/, "_")
    |> String.trim("_")
  end

  defp pad2(i) when is_integer(i), do: i |> Integer.to_string() |> String.pad_leading(2, "0")
end
