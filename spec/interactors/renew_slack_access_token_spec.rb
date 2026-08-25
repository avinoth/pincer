require "rails_helper"

RSpec.describe RenewSlackAccessToken do
  let(:workspace) { create(:slack_workspace, :expired, access_token: "old", refresh_token: "old_refresh") }

  it "refreshes and persists the workspace tokens" do
    allow(Slack::Request::TokenAuth).to receive(:new)
      .with("old_refresh")
      .and_return(instance_double(Slack::Request::TokenAuth, refresh: slack_auth_response))

    result = described_class.call(workspace: workspace)

    expect(result).to be_success
    expect(workspace.reload.access_token).not_to eq("old")
    expect(workspace.access_token_expires_at).to be_present
  end

  context "when the refresh fails" do
    it "fails" do
      allow(Slack::Request::TokenAuth).to receive(:new)
        .and_return(instance_double(Slack::Request::TokenAuth, refresh: nil))

      result = described_class.call(workspace: workspace)
      expect(result).to be_failure
      expect(result.error).to eq(:renewal_failed)
    end
  end
end
