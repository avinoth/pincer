# Refresh-token grant for Slack token rotation.
class Slack::Request::TokenAuth
  def initialize(refresh_token)
    @refresh_token = refresh_token
  end

  def refresh
    client = Slack::Web::Client.new

    result = client.oauth_v2_access(
      client_id: ENV["SLACK_CLIENT_ID"],
      client_secret: ENV["SLACK_CLIENT_SECRET"],
      refresh_token: @refresh_token,
      grant_type: "refresh_token",
    )

    Slack::Response::Auth.new(result)
  rescue => e
    Bugsnag.notify(e)
    nil
  end
end
