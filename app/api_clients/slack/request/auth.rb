# Initial OAuth code -> token exchange for the app install flow.
# Uses an unauthenticated client; credentials are passed explicitly.
class Slack::Request::Auth
  def initialize(code)
    @code = code
  end

  def perform_oauth(redirect_uri)
    client = Slack::Web::Client.new

    result = client.oauth_v2_access(
      client_id: ENV["SLACK_CLIENT_ID"],
      client_secret: ENV["SLACK_CLIENT_SECRET"],
      redirect_uri: redirect_uri,
      code: @code,
    )

    Slack::Response::Auth.new(result)
  rescue => e
    Bugsnag.notify(e)
    nil
  end
end
