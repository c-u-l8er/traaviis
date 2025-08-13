defmodule FSMApp.Repo do
  use Ecto.Repo,
    otp_app: :fsm_app,
    adapter: Ecto.Adapters.Postgres
end
