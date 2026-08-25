# Rate-limiting for the admin surfaces (/admin, /good_job) — the only real
# perimeter around them, since both sit behind a single shared Basic Auth
# credential with no per-admin accounts or IP allowlist (see
# config/initializers/rails_admin.rb, config/initializers/good_job.rb).
#
# rack-attack self-inserts into the middleware stack via its Railtie; no
# manual `config.middleware.use` needed here.
#
# Cache: defaults to Rails.cache, which is :solid_cache_store in production
# (fine — persistent/shared across processes) but :null_store in test, so
# throttle/blocklist specs must override Rack::Attack.cache.store with an
# in-memory store to actually observe blocking.
class Rack::Attack
  ADMIN_PATHS = %w[/admin /good_job].freeze

  # Cap request volume per IP against the admin surfaces, regardless of
  # whether the request is authenticated.
  throttle("admin/req/ip", limit: 60, period: 5.minutes) do |req|
    req.ip if ADMIN_PATHS.any? { |path| req.path.start_with?(path) }
  end

  # After 5 failed Basic Auth attempts in 5 minutes from one IP, block that IP
  # for 20 minutes. Runs pre-dispatch, so we decode the raw Authorization
  # header ourselves via AdminAuth rather than relying on the controller/
  # engine having already rejected the request.
  #
  # Rack::Attack::Fail2Ban.filter blocks the very request that trips its
  # condition (fail! always returns true) — fine for blocking bad request
  # *patterns* outright, but wrong here: it would 403 the 1st-5th wrong-
  # credential attempts too, when they should still 401 normally (a mistyped
  # password isn't itself malicious). Allow2Ban is the subclass built for
  # this: fail! returns false until the count crosses maxretry, so attempts
  # 1-5 pass through untouched and only the 6th+ (within the ban window) get
  # blocked.
  blocklist("admin/fail2ban") do |req|
    next false unless ADMIN_PATHS.any? { |path| req.path.start_with?(path) }

    Rack::Attack::Allow2Ban.filter("admin-fail2ban-#{req.ip}", maxretry: 5, findtime: 5.minutes, bantime: 20.minutes) do
      !AdminAuth.valid_authorization_header?(req.get_header("HTTP_AUTHORIZATION"))
    end
  end
end
