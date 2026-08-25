require "rails_helper"

RSpec.describe "Sessions (Slack OIDC)", type: :request do
  before { OmniAuth.config.test_mode = true }
  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:slack] = nil
    Rails.application.env_config.delete("omniauth.auth")
  end

  def mock_slack_auth(uid:, team_id:)
    auth = OmniAuth::AuthHash.new(
      provider: "slack",
      uid: uid,
      extra: { raw_info: { "https://slack.com/team_id" => team_id } },
    )
    OmniAuth.config.mock_auth[:slack] = auth
    Rails.application.env_config["omniauth.auth"] = auth
  end

  describe "GET /auth/slack/callback" do
    it "signs in an existing active user" do
      organization = create(:organization, status: :active)
      workspace = create(:slack_workspace, organization: organization)
      user = create(:user, organization: organization, provider_uid: "U123")
      mock_slack_auth(uid: "U123", team_id: workspace.identifier)

      get "/auth/slack/callback"

      expect(response).to redirect_to("http://localhost:3000?login=success")
    end

    it "redirects with no_org when the workspace isn't installed" do
      mock_slack_auth(uid: "U999", team_id: "T_UNKNOWN")

      get "/auth/slack/callback"

      expect(response).to redirect_to("http://localhost:3000?login=no_org")
    end

    it "imports a new member when the workspace exists" do
      organization = create(:organization, status: :active)
      workspace = create(:slack_workspace, organization: organization)
      new_user = build_stubbed(:user, organization: organization)
      allow(CreateUserFromSlack).to receive(:call).and_return(double(success?: true, user: new_user))
      mock_slack_auth(uid: "U_NEW", team_id: workspace.identifier)

      get "/auth/slack/callback"

      expect(CreateUserFromSlack).to have_received(:call)
        .with(hash_including(slack_user_id: "U_NEW", organization: organization, user_role: :member))
      expect(response).to redirect_to("http://localhost:3000?login=success")
    end
  end
end
