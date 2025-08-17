defmodule FSMAppWeb.Router do
  use FSMAppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug FSMAppWeb.Auth.Pipeline
    plug :put_root_layout, html: {FSMAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :public do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FSMAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

    # Public routes (no authentication required)
  scope "/", FSMAppWeb do
    pipe_through :public

    get "/", PageController, :home
    get "/sign-in", SessionController, :new
    post "/sign-in", SessionController, :create
    get "/register", RegistrationController, :new
    post "/register", RegistrationController, :create

    # Alternative auth routes (aliases to the above)
    get "/auth/login", SessionController, :new
    post "/auth/login", SessionController, :create
  end

  # Authenticated routes (authentication required)
  scope "/", FSMAppWeb do
    pipe_through :browser

    delete "/sign-out", SessionController, :delete

    live_session :default,
      on_mount: [FSMAppWeb.Auth.OnMountCurrentUser, FSMAppWeb.Auth.RequireAuthLive] do
      # Root path serves splash page; authenticated dashboard available at /control-panel
      live "/control-panel", ControlPanelLive
      live "/fsms", FSMSLive
      live "/fsms/:id", FSMSLive
      live "/tenants", TenantsLive
      live "/members", MembersLive
      live "/modules", ModulesLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", FSMAppWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:fsm_app, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FSMAppWeb.Telemetry
    end
  end
end
