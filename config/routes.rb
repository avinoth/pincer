Rails.application.routes.draw do
  # Admin panel (RailsAdmin) — gated by shared Basic Auth, see
  # config/initializers/rails_admin.rb.
  mount RailsAdmin::Engine => "/admin", as: "rails_admin"

  # Health check for load balancers / uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  # GoodJob dashboard.
  mount GoodJob::Engine => "/good_job"

  # Slack app install + events.
  namespace :slack do
    get :install, to: "auth#install"
    get :setup, to: "auth#setup"
    post :events, to: "events#create"
    post :interactions, to: "events#interactions"
    post :command, to: "events#command"
    post :options_for_select, to: "events#options_for_select"
  end

  # "Sign in with Slack" (OmniAuth OpenID Connect).
  # GET /auth/slack is intercepted by the OmniAuth middleware (request phase).
  get "/auth/slack/callback", to: "sessions#create"
  get "/auth/failure", to: "sessions#failure"
  delete "/logout", to: "sessions#destroy"
end
