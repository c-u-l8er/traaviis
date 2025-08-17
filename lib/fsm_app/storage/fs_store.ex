defmodule FSMApp.Storage.FSStore do
  @moduledoc """
  Simple filesystem-backed key-value collections using JSON arrays.

  Collections are stored under `./data/<namespace>/<collection>.json`.
  This module provides helpers to load and persist entire collections
  safely, creating directories as needed.
  """

  defp data_root do
    base_dir = case Application.get_env(:fsm_app, :env) do
      :test ->
        Application.get_env(:fsm_app, :test_data_dir, "test/tmp/data")
      _ ->
        "data"
    end
    Path.expand(base_dir)
  end

  @type collection :: String.t()
  @type record :: map()

  @spec load(String.t(), String.t()) :: [record()]
  def load(namespace, collection) do
    path = path_for(namespace, collection)
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, list} when is_list(list) -> list
          _ -> []
        end
      {:error, :enoent} -> []
      {:error, _} -> []
    end
  end

  @spec persist(String.t(), String.t(), [record()]) :: :ok | {:error, term()}
  def persist(namespace, collection, records) when is_list(records) do
    with {:ok, json} <- Jason.encode(records, pretty: true),
         :ok <- ensure_dir(namespace),
         tmp <- temp_path_for(namespace, collection),
         :ok <- File.write(tmp, json),
         :ok <- File.rename(tmp, path_for(namespace, collection)) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  @spec upsert(String.t(), String.t(), (-> record()), (record() -> boolean()), (record() -> record())) :: {:ok, record()} | {:error, term()}
  def upsert(namespace, collection, new_fun, match_fun, update_fun) do
    records = load(namespace, collection)
    {found, others} = Enum.split_with(records, match_fun)
    case found do
      [existing | _] ->
        updated = update_fun.(existing)
        case persist(namespace, collection, [updated | Enum.reject(others, match_fun)]) do
          :ok -> {:ok, updated}
          {:error, reason} -> {:error, reason}
        end
      [] ->
        new_record = new_fun.()
        case persist(namespace, collection, [new_record | records]) do
          :ok -> {:ok, new_record}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp ensure_dir(namespace) do
    File.mkdir_p(Path.join(data_root(), namespace))
  end

  defp path_for(namespace, collection) do
    Path.join([data_root(), namespace, collection <> ".json"]) |> Path.expand()
  end

  defp temp_path_for(namespace, collection) do
    Path.join([data_root(), namespace, ".#{collection}.tmp"]) |> Path.expand()
  end
end
