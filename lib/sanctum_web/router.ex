defmodule SanctumWeb.Router do
  use SanctumWeb, :router

  import Oban.Web.Router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug SanctumWeb.Plugs.ContentSecurityPolicy
    plug :fetch_session
    plug Sentry.Plug.LiveViewContext
    plug :fetch_live_flash
    plug :put_root_layout, html: {SanctumWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
    plug :set_sentry_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  # Conn-level admin gate for non-LiveView-macro routes (e.g. the Oban
  # dashboard) that can't use the :live_admin_required on_mount hook.
  pipeline :require_admin do
    plug :ensure_admin
  end

  # Route-scoped CSP that permits the Oban dashboard's inline bootstrap script
  # (via a per-request nonce) without loosening the app-wide policy.
  pipeline :oban_csp do
    plug :put_oban_csp
  end

  # Minimal stack for CI-driven webhooks — token auth happens in the
  # controller, so no session/auth plugs are needed.
  pipeline :deploy_hooks do
    plug :accepts, ["json"]
  end

  scope "/", SanctumWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes,
      on_mount: [
        {SanctumWeb.Presence, :track},
        {SanctumWeb.DeployNotice, :notify}
      ] do
      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {SanctumWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {SanctumWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {SanctumWeb.LiveUserAuth, :live_no_user}

      live "/", GameLive.Index, :index
      live "/games/new", GameLive.New, :new
      live "/games/:id", GameLive.Show, :show

      # Signed-in user's profile (username claim; settings stack here later).
      live "/profile", ProfileLive.Index, :index

      # Public content browser — waves → products → card sets → cards.
      live "/browse", BrowseLive.Index, :index
      live "/browse/:pack", BrowseLive.Show, :show

      # Public card pool + card detail (catalog reads are unauthenticated).
      live "/cards", CardLive.Pool, :index
      live "/cards/:id", CardLive.Detail, :show

      # Public deck browser + detail (deck reads are unauthenticated).
      # /decks/new must precede /decks/:id or "new" binds as an :id.
      live "/decks", DeckLive.Index, :index
      live "/decks/new", DeckLive.New, :new
      live "/decks/:id", DeckLive.Show, :show
      live "/decks/:id/build", DeckLive.Build, :build

      # Reference page for the card/deck search query language.
      live "/search-help", SearchHelpLive, :index

      # Public "Flavor Town" flavor-text guessing mini-game.
      live "/flavor-town", GuessLive.Play, :index

      # Public deck-collection stats.
      live "/stats", StatsLive.Index, :index

      # Dev playground for refining the comic stat badges.
      live "/dev/stat-badges", DevLive.StatBadges, :index
    end

    ash_authentication_live_session :admin_routes,
      on_mount: [
        {SanctumWeb.LiveUserAuth, :live_admin_required},
        {SanctumWeb.Presence, :track},
        {SanctumWeb.DeployNotice, :notify}
      ] do
      # Admin landing page — system health + links to admin surfaces.
      live "/admin", AdminLive.Index, :index

      # Admin card catalog management (data table + CRUD + sync).
      live "/admin/cards", CardLive.Index, :index
      live "/admin/cards/new", CardLive.Form, :new
      live "/admin/cards/sync", CardLive.Sync, :index
      live "/admin/cards/:id/edit", CardLive.Form, :edit

      live "/admin/cards/:id", CardLive.Show, :show
      live "/admin/cards/:id/show/edit", CardLive.Show, :edit
    end
  end

  # Oban Web job dashboard — admin-only, available in every environment.
  #
  # oban_dashboard/2 builds its OWN live_session with a fixed session extractor
  # that drops our Ash auth token, so the LiveView on_mount hooks can't see
  # current_user. We gate it at the plug level instead (:require_admin runs
  # against conn.assigns.current_user, populated by load_from_session). Oban Web
  # also emits an inline bootstrap <script>, which our strict prod CSP would
  # block — :oban_csp swaps in a scoped, nonce-based policy for this route only.
  scope "/admin" do
    pipe_through [:browser, :require_admin, :oban_csp]

    oban_dashboard("/oban", csp_nonce_assign_key: :csp_nonce)
  end

  scope "/", SanctumWeb do
    pipe_through :browser

    auth_routes AuthController, Sanctum.Accounts.User, path: "/auth"

    sign_out_route AuthController,
                   "/sign-out",
                   overrides: [
                     SanctumWeb.AuthOverrides,
                     AshAuthentication.Phoenix.Overrides.Default
                   ]

    # Custom live_view: /register is our enumeration-safe email-first flow
    # (SanctumWeb.AuthSignInLive) instead of the stock create-or-error form;
    # sign-in and reset render the stock component unchanged.
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  live_view: SanctumWeb.AuthSignInLive,
                  on_mount: [{SanctumWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    SanctumWeb.AuthOverrides,
                    AshAuthentication.Phoenix.Overrides.Default
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [SanctumWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the confirmation strategy
    confirm_route Sanctum.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [SanctumWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Sanctum.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [SanctumWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", SanctumWeb do
  #   pipe_through :api
  # end

  # CI-only webhook: announces an imminent deploy to connected users
  # (bearer-token guarded; see SanctumWeb.DeployNoticeController).
  scope "/internal", SanctumWeb do
    pipe_through :deploy_hooks

    post "/deploy-notice", DeployNoticeController, :create
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:sanctum, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SanctumWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  if Application.compile_env(:sanctum, :dev_routes) do
    import AshAdmin.Router

    # Nested under /admin/ash so the admin landing page can own /admin.
    scope "/admin/ash" do
      pipe_through :browser

      ash_admin "/"
    end
  end

  # Tags Sentry events from the request process with the user id (no PII).
  # LiveView processes set their own context in SanctumWeb.LiveUserAuth.
  defp set_sentry_user(conn, _opts) do
    case conn.assigns[:current_user] do
      %{id: id} -> Sentry.Context.set_user_context(%{id: id})
      _ -> :ok
    end

    conn
  end

  # Redirects non-admins away from admin-only conn routes (the Oban dashboard).
  defp ensure_admin(conn, _opts) do
    case conn.assigns[:current_user] do
      %{admin: true} ->
        conn

      _ ->
        conn
        |> Phoenix.Controller.put_flash(:error, "You do not have permission to access that page.")
        |> Phoenix.Controller.redirect(to: "/")
        |> halt()
    end
  end

  # Emits a per-request nonce (consumed by the Oban dashboard's inline script)
  # and replaces the app-wide CSP header for this route only. Styles stay
  # 'unsafe-inline' because Oban Web uses inline style attributes a nonce can't
  # cover; scripts are locked to self + the nonce.
  defp put_oban_csp(conn, _opts) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    policy =
      "default-src 'self';" <>
        "script-src 'self' 'nonce-#{nonce}';" <>
        "style-src 'self' 'unsafe-inline';" <>
        "img-src 'self' data:;" <>
        "font-src 'self' data:;" <>
        "connect-src 'self';"

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy)
  end
end
