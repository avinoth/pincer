require "rails_helper"

RSpec.describe "Admin panel rate limiting", type: :request do
  around do |example|
    original_env = ENV.to_hash.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    ENV["ADMIN_USERNAME"] = "admin"
    ENV["ADMIN_PASSWORD"] = "s3cret-pw"

    # Rails.cache is :null_store in test, so rack-attack's fail2ban/allow2ban
    # counters (which live in Rack::Attack.cache, defaulting to Rails.cache)
    # never persist between requests — nothing would ever actually get
    # banned. Swap in a real in-memory store for the duration of this spec,
    # and reset it after so other specs' requests to /admin aren't
    # accidentally throttled/blocked by leftover state.
    original_cache = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

    example.run

    Rack::Attack.cache.store = original_cache
    original_env.each { |k, v| ENV[k] = v }
  end

  def basic_auth_header(username, password)
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(username, password) }
  end

  it "blocks an IP after repeated failed Basic Auth attempts, but lets the first several through as normal 401s" do
    # maxretry: 5 (see config/initializers/rack_attack.rb) — the 1st-5th
    # failed attempts should still 401 normally (a mistyped password isn't
    # itself malicious); only once the count crosses the threshold does the
    # IP get blocklisted.
    5.times do
      get "/admin", headers: basic_auth_header("admin", "wrong-pw")
      expect(response).to have_http_status(:unauthorized)
    end

    get "/admin", headers: basic_auth_header("admin", "wrong-pw")

    expect(response).to have_http_status(:forbidden)
  end

  it "blocks the IP from /good_job too, once banned via /admin (shared per-IP discriminator)" do
    6.times { get "/admin", headers: basic_auth_header("admin", "wrong-pw") }

    get "/good_job", headers: basic_auth_header("admin", "wrong-pw")

    expect(response).to have_http_status(:forbidden)
  end

  it "does not block an IP that has only ever sent valid credentials" do
    10.times do
      get "/admin", headers: basic_auth_header("admin", "s3cret-pw")
      expect(response).to have_http_status(:ok)
    end
  end
end
