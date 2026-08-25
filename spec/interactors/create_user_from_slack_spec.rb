require "rails_helper"

RSpec.describe CreateUserFromSlack do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }

  it "finds an existing user by provider_uid without hitting Slack" do
    existing = create(:user, organization: organization, provider_uid: "U9")
    allow(Slack::Request::UserById).to receive(:new)

    result = described_class.call(organization: organization, slack_user_id: "U9")

    expect(result).to be_success
    expect(result.user).to eq(existing)
    expect(Slack::Request::UserById).not_to have_received(:new)
  end

  it "fetches and creates a new user from Slack when none exists locally" do
    allow(Slack::Request::UserById).to receive(:new)
      .and_return(instance_double(Slack::Request::UserById, get: slack_user_response))

    result = described_class.call(organization: organization, slack_user_id: "U00000000")

    expect(result).to be_success
    expect(result.user).to be_persisted
    expect(result.user.provider_uid).to eq("U00000000")
  end

  it "fails with :bot_user and creates nothing when the fetched Slack user is a bot" do
    bot_payload = slack_payload("user_by_id")
    bot_payload["user"]["is_bot"] = true
    allow(Slack::Request::UserById).to receive(:new)
      .and_return(instance_double(Slack::Request::UserById, get: Slack::Response::User.new(bot_payload)))

    result = described_class.call(organization: organization, slack_user_id: "U00000000")

    expect(result).to be_failure
    expect(result.error).to eq(:bot_user)
    expect(organization.users.count).to eq(0)
  end

  it "fails with :user_fetch_failed when the Slack lookup is unsuccessful" do
    allow(Bugsnag).to receive(:notify)
    allow(Slack::Request::UserById).to receive(:new)
      .and_return(instance_double(Slack::Request::UserById, get: Slack::Response::User.new("ok" => false)))

    result = described_class.call(organization: organization, slack_user_id: "U_MISSING")

    expect(result).to be_failure
    expect(result.error).to eq(:user_fetch_failed)
    expect(organization.users.count).to eq(0)
  end

  describe "organization time_zone seeding" do
    it "seeds organization.time_zone from the installer's Slack tz on a fresh install (organization_created owner path)" do
      expect(organization.time_zone).to eq("UTC")
      allow(Slack::Request::UserById).to receive(:new)
        .and_return(instance_double(Slack::Request::UserById, get: slack_user_response))

      result = described_class.call(organization: organization, slack_user_id: "U00000000", user_role: :owner)

      expect(result).to be_success
      expect(result.user).to be_owner
      expect(organization.reload.time_zone).to eq("Asia/Kolkata")
    end

    it "re-seeds organization.time_zone on a re-install, from whatever tz the installer's Slack profile now reports" do
      # First install.
      allow(Slack::Request::UserById).to receive(:new)
        .and_return(instance_double(Slack::Request::UserById, get: slack_user_response))
      described_class.call(organization: organization, slack_user_id: "U00000000", user_role: :owner)
      expect(organization.reload.time_zone).to eq("Asia/Kolkata")

      # Re-install (OrganizationSignupFromSlack -> CreateUserFromSlack runs again): a workspace
      # re-authorizing with a different owner-role installer, whose Slack tz differs.
      reinstall_payload = slack_payload("user_by_id")
      reinstall_payload["user"]["id"] = "U_REINSTALL_OWNER"
      reinstall_payload["user"]["tz"] = "America/Los_Angeles"
      allow(Slack::Request::UserById).to receive(:new)
        .and_return(instance_double(Slack::Request::UserById, get: Slack::Response::User.new(reinstall_payload)))

      result = described_class.call(organization: organization, slack_user_id: "U_REINSTALL_OWNER", user_role: :owner)

      expect(result).to be_success
      expect(organization.reload.time_zone).to eq("America/Los_Angeles")
    end

    it "does not touch organization.time_zone for a non-owner user" do
      allow(Slack::Request::UserById).to receive(:new)
        .and_return(instance_double(Slack::Request::UserById, get: slack_user_response))

      described_class.call(organization: organization, slack_user_id: "U00000000", user_role: :member)

      expect(organization.reload.time_zone).to eq("UTC")
    end
  end
end
