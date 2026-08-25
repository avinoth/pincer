source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache and Action Cable
gem "solid_cache"
gem "solid_cable"

# Background jobs (Postgres-backed) [https://github.com/bensheldon/good_job]
gem "good_job"

# Service objects / organizer pattern [https://github.com/collectiveidea/interactor-rails]
gem "interactor-rails"

# Slack Web API client [https://github.com/slack-ruby/slack-ruby-client]
gem "slack-ruby-client"

# LLM orchestration (structured output + provider routing) [https://rubyllm.com]
gem "ruby_llm"

# Slack OAuth — "Sign in with Slack" via OpenID Connect
gem "omniauth"
gem "omniauth_openid_connect"

# Error tracking
gem "bugsnag"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.0"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
gem "rack-cors"

# Admin panel for CRUD/search across app models [https://github.com/railsadminteam/rails_admin]
gem "rails_admin", "~> 3.3"
# Asset pipeline rails_admin needs (app has no asset pipeline today)
gem "sassc-rails"
# Rate limiting / brute-force throttling for the admin + GoodJob dashboards
gem "rack-attack", "~> 6.8"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Testing
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "shoulda-matchers"
  gem "webmock"

  # Debugging + local env
  gem "pry-rails"
  gem "dotenv-rails"
end
