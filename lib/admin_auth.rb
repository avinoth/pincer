# Single source of truth for the shared admin credential check. Used by
# RailsAdmin's authenticate_with block, GoodJob's Basic Auth middleware, and
# rack-attack's fail2ban filter (which runs pre-dispatch and only has the raw
# Authorization header to work with).
#
# Fails closed: if ADMIN_USERNAME or ADMIN_PASSWORD isn't set, valid? always
# returns false, so /admin and /good_job are simply unreachable rather than
# raising on boot.
module AdminAuth
  module_function

  def valid?(username, password)
    expected_username = ENV["ADMIN_USERNAME"]
    expected_password = ENV["ADMIN_PASSWORD"]
    return false if expected_username.blank? || expected_password.blank?
    return false if username.blank? || password.blank?

    username_match = ActiveSupport::SecurityUtils.secure_compare(username, expected_username)
    password_match = ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
    username_match && password_match
  end

  # Decodes a raw `Authorization` header value (e.g. "Basic dXNlcjpwYXNz") and
  # validates it. Used by rack-attack, which runs before the request reaches
  # the controller/engine layer where Rack::Auth::Basic would normally decode
  # this for us.
  def valid_authorization_header?(header_value)
    return false if header_value.blank?

    scheme, encoded_credentials = header_value.split(" ", 2)
    return false unless scheme&.casecmp("basic")&.zero?
    return false if encoded_credentials.blank?

    decoded = Base64.decode64(encoded_credentials)
    username, password = decoded.split(":", 2)
    valid?(username, password)
  rescue ArgumentError
    false
  end
end
