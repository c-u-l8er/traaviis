defmodule FSMAppWeb.Presence do
  @moduledoc """
  Phoenix Presence for tracking user activity in tenant channels.

  Tracks active users within tenant boundaries and provides
  real-time user presence information for collaborative features.
  """

  use Phoenix.Presence,
    otp_app: :fsm_app,
    pubsub_server: FSMApp.PubSub

  @doc """
  Get list of users present in a tenant.
  """
  def get_tenant_users(tenant_id) do
    list("tenant:#{tenant_id}")
    |> Enum.map(fn {user_id, %{metas: metas}} ->
      # Use the most recent metadata
      latest_meta = List.first(metas)
      %{
        user_id: user_id,
        user: latest_meta[:user],
        joined_at: latest_meta[:joined_at],
        permissions: latest_meta[:permissions],
        last_seen: latest_meta[:phx_ref_time] || DateTime.utc_now()
      }
    end)
  end

  @doc """
  Check if a user is online in a tenant.
  """
  def user_online?(tenant_id, user_id) do
    case get_by_key("tenant:#{tenant_id}", user_id) do
      [] -> false
      _presences -> true
    end
  end

  @doc """
  Get count of active users in tenant.
  """
  def tenant_user_count(tenant_id) do
    "tenant:#{tenant_id}"
    |> list()
    |> map_size()
  end

  @doc """
  Track user activity across multiple tenants.
  """
  def track_user_activity(user_id, activity_data) do
    # This could be used to track user activity across tenants
    # for analytics and user behavior insights
    Phoenix.PubSub.broadcast(FSMApp.PubSub, "user_activity:#{user_id}", {
      :user_activity,
      Map.merge(activity_data, %{
        user_id: user_id,
        timestamp: DateTime.utc_now()
      })
    })
  end
end
