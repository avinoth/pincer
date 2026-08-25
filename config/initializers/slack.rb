# "Sign in with Slack" via OpenID Connect (returning-user login).
#
# This is distinct from the app *install* flow (Slack::AuthController), which
# performs the bot-token OAuth exchange directly via slack-ruby-client. Here we
# only need the user's identity (uid + team_id), so the OIDC scope is :openid.
#
# Callback: GET /auth/slack/callback -> SessionsController#create
# Failure:  GET /auth/failure        -> SessionsController#failure

OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.silence_get_warning = true
OmniAuth.config.logger = Rails.logger

Rails.application.config.middleware.use OmniAuth::Strategies::OpenIDConnect, {
  name: :slack,
  issuer: "https://slack.com",
  discovery: true,
  scope: [ :openid ],
  response_type: :code,
  client_options: {
    port: 443,
    scheme: "https",
    host: "slack.com",
    identifier: ENV["SLACK_CLIENT_ID"],
    secret: ENV["SLACK_CLIENT_SECRET"],
    redirect_uri: "https://#{ENV['BASE_URL']}/auth/slack/callback"
  }
}
