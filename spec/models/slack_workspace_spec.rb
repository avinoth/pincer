require "rails_helper"

RSpec.describe SlackWorkspace, type: :model do
  subject { build(:slack_workspace) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:identifier) }
  it { is_expected.to validate_presence_of(:access_token) }
  it { is_expected.to validate_presence_of(:refresh_token) }
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to validate_uniqueness_of(:organization) }

  describe "#token_expired?" do
    it { expect(build(:slack_workspace, access_token_expires_at: 1.hour.from_now).token_expired?).to be(false) }
    it { expect(build(:slack_workspace, :expired).token_expired?).to be(true) }
    it { expect(build(:slack_workspace, access_token_expires_at: nil).token_expired?).to be(true) }
  end

  describe "#update_details_from_slack!" do
    it "persists refreshed tokens" do
      workspace = create(:slack_workspace, access_token: "old", refresh_token: "old_r")
      workspace.update_details_from_slack!(slack_auth_response)

      expect(workspace.reload.access_token).not_to eq("old")
      expect(workspace.refresh_token).not_to eq("old_r")
      expect(workspace.access_token_expires_at).to be_present
    end
  end
end
