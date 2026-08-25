class PerformSlackOauth
  include Interactor

  def call
    response = Slack::Request::Auth.new(context.code).perform_oauth(redirect_uri)

    if response.nil? || !response.success?
      Bugsnag.notify("Slack OAuth failed", { code: context.code, response: response })
      context.fail!(error: :invalid_response)
    end

    context.slack_response = response
  end

  private

  # Must exactly match the redirect_uri used to build the install authorize URL
  # in Slack::AuthController#install.
  def redirect_uri
    "https://#{ENV['BASE_URL']}/slack/setup"
  end
end
