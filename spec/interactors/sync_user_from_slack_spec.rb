require "rails_helper"

RSpec.describe SyncUserFromSlack do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }

  def slack_user(overrides = {})
    Slack::Type::User.new({
      id: "U9",
      real_name: "New Person",
      tz: "America/New_York",
      profile: { email: "new@example.com" }
    }.merge(overrides).with_indifferent_access)
  end

  it "creates a new user when none exists for this organization" do
    result = described_class.call(organization: organization, slack_user: slack_user)

    expect(result).to be_success
    expect(result.user).to be_persisted
    expect(result.user.provider_uid).to eq("U9")
    expect(result.user.role).to eq("member")
  end

  it "updates an existing user instead of creating a duplicate (idempotent on retried delivery)" do
    existing = create(:user, organization: organization, provider_uid: "U9", full_name: "Old Name")

    result = described_class.call(organization: organization, slack_user: slack_user(real_name: "New Name"))

    expect(result.user).to eq(existing)
    expect(organization.users.count).to eq(1)
    expect(existing.reload.full_name).to eq("New Name")
  end

  it "skips bot users" do
    result = described_class.call(organization: organization, slack_user: slack_user(is_bot: true))

    expect(result.user).to be_nil
    expect(organization.users.count).to eq(0)
  end

  it "skips deleted users" do
    result = described_class.call(organization: organization, slack_user: slack_user(deleted: true))

    expect(result.user).to be_nil
    expect(organization.users.count).to eq(0)
  end
end
