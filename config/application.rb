require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Namespace holder for all AI/LLM code under app/ai (see push_dir below).
module Ai; end

module Pincer
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # All AI/LLM code lives under app/ai and is namespaced under Ai::. Zeitwerk
    # otherwise collapses app/* into roots (expecting top-level constants), so we
    # pre-register the directory with an explicit namespace; Rails then skips it
    # when computing default autoload roots.
    Rails.autoloaders.main.push_dir("#{root}/app/ai", namespace: Ai)

    # Rails only auto-collapses `app/*/concerns` (one level deep). This concerns
    # dir sits three levels down, so collapse it explicitly: Capabilities lives
    # at Slack::Messages::Capabilities, not Slack::Messages::Concerns::Capabilities.
    Rails.autoloaders.main.collapse("#{root}/app/api_clients/slack/messages/concerns")

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # API mode also strips the middleware RailsAdmin/GoodJob's dashboard need
    # (both are full-stack engines with views + non-Turbo form fallback): a
    # method-override shim for their <form> "_method" params, and flash for
    # their redirect-with-notice flows.
    config.middleware.use Rack::MethodOverride
    config.middleware.use ActionDispatch::Flash

    # API mode strips session/cookie middleware. We re-add it so we can issue an
    # HttpOnly cookie session and so OmniAuth works.
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
      key: "_pincer_session",
      same_site: :lax,
      secure: Rails.env.production?

    # Postgres-backed background jobs.
    config.active_job.queue_adapter = :good_job

    # Generate bigint primary keys (Rails default) for new tables.
  end
end
