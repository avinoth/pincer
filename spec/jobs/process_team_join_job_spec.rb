require "rails_helper"

RSpec.describe ProcessTeamJoinJob do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:user_hash) { { "id" => "U9", "real_name" => "New Person", "profile" => { "email" => "new@example.com" } } }

  it "syncs the user for the resolved organization" do
    expect(SyncUserFromSlack).to receive(:call).with(
      organization: organization, slack_user: an_instance_of(Slack::Type::User)
    ).and_return(double(failure?: false))

    described_class.perform_now(team_id: workspace.identifier, user: user_hash)
  end

  it "reports to Bugsnag when the sync fails" do
    allow(SyncUserFromSlack).to receive(:call).and_return(double(failure?: true, error: :user_sync_failed))
    expect(Bugsnag).to receive(:notify)

    described_class.perform_now(team_id: workspace.identifier, user: user_hash)
  end

  it "no-ops for an unknown workspace" do
    expect(SyncUserFromSlack).not_to receive(:call)
    expect { described_class.perform_now(team_id: "T_UNKNOWN", user: user_hash) }.not_to raise_error
  end
end
