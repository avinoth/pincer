require "rails_helper"

RSpec.describe "Slack::Auth", type: :request do
  around do |example|
    original = ENV.to_hash.slice("SLACK_CLIENT_ID", "BASE_URL", "FRONTEND_URL")
    ENV["SLACK_CLIENT_ID"] = "client-123"
    ENV["BASE_URL"] = "localhost:3001"
    ENV["FRONTEND_URL"] = "http://localhost:3000"
    example.run
    original.each { |k, v| ENV[k] = v }
  end

  describe "GET /slack/install" do
    it "redirects to Slack's authorize URL with bot scopes" do
      get "/slack/install"

      expect(response).to have_http_status(:found)
      expect(response.location).to start_with("https://slack.com/oauth/v2/authorize")
      expect(response.location).to include("client_id=client-123")
      expect(response.location).to include("users%3Aread.email")
      expect(response.location).to include(CGI.escape("https://localhost:3001/slack/setup"))
    end
  end

  describe "GET /slack/setup" do
    it "redirects to the frontend with an error when Slack returns error" do
      get "/slack/setup", params: { error: "access_denied" }

      expect(response).to redirect_to("http://localhost:3000?signup=error")
    end

    it "signs in and deep-links into the Pincer app in Slack on success" do
      user = create(:user)
      slack_response = double(app_id: "A123", team_id: "T123")
      allow(OrganizationSignupFromSlack).to receive(:call)
        .and_return(double(success?: true, user: user, slack_response: slack_response))

      get "/slack/setup", params: { code: "abc" }

      expect(response).to redirect_to("https://slack.com/app_redirect?app=A123&team=T123")
    end

    it "redirects with an error when signup fails" do
      allow(OrganizationSignupFromSlack).to receive(:call).and_return(double(success?: false))

      get "/slack/setup", params: { code: "abc" }

      expect(response).to redirect_to("http://localhost:3000?signup=error")
    end
  end
end
