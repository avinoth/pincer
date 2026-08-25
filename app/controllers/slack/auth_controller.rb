class Slack::AuthController < ApplicationController
  SLACK_BOT_SCOPES = %w[
    app_mentions:read
    assistant:write
    channels:read
    chat:write
    chat:write.customize
    chat:write.public
    groups:read
    groups:write
    im:history
    im:write
    mpim:history
    team:read
    users:read
    users:read.email
  ].freeze

  # GET /slack/install — kick off the Slack app install (bot OAuth).
  def install
    query = {
      client_id: ENV.fetch("SLACK_CLIENT_ID"),
      redirect_uri: redirect_uri,
      scope: SLACK_BOT_SCOPES.join(",")
    }.to_param

    redirect_to("https://slack.com/oauth/v2/authorize?#{query}", allow_other_host: true)
  end

  # GET /slack/setup — Slack redirects here with ?code= (or ?error=).
  def setup
    if params[:error].present?
      Bugsnag.notify(params[:error])
      return redirect_to(frontend_url(signup: "error"), allow_other_host: true)
    end

    result = OrganizationSignupFromSlack.call(code: params[:code])

    if result.success?
      sign_in(result.user)
      redirect_to(slack_app_redirect_url(result.slack_response), allow_other_host: true)
    else
      redirect_to(frontend_url(signup: "error"), allow_other_host: true)
    end
  end

  private

  # Must exactly match PerformSlackOauth#redirect_uri.
  def redirect_uri
    "https://#{ENV['BASE_URL']}/slack/setup"
  end

  # Deep-links straight into the Pincer app/bot inside Slack (desktop app if
  # installed, else slack.com), rather than landing the user back on our
  # own frontend after install.
  def slack_app_redirect_url(slack_response)
    query = { app: slack_response.app_id, team: slack_response.team_id }.to_param
    "https://slack.com/app_redirect?#{query}"
  end
end
