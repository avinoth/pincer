# Be sure to restart your server when you modify this file.
#
# Allow the Next.js frontend to call this API with credentials (the HttpOnly
# session cookie). Origins must be explicit when credentials are enabled — a
# wildcard "*" is not permitted with `credentials: true`.

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_URL", "http://localhost:3000")

    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      credentials: true
  end
end
