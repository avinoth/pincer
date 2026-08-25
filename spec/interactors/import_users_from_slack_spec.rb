require "rails_helper"

RSpec.describe ImportUsersFromSlack do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }

  before do
    allow(Slack::Request::UserList).to receive(:new)
      .and_return(instance_double(Slack::Request::UserList, get: slack_user_list_response))
  end

  it "imports human members, skipping bots and deleted users" do
    result = described_class.call(organization: organization)

    expect(result).to be_success
    expect(organization.users.count).to eq(1)

    user = organization.users.first
    expect(user.provider_uid).to eq("U00000000")
    expect(user.role).to eq("member")
  end

  context "when Slack returns an error" do
    before do
      errored = Slack::Response::UserList.new({ "ok" => false, "error" => "invalid_auth" })
      allow(Slack::Request::UserList).to receive(:new)
        .and_return(instance_double(Slack::Request::UserList, get: errored))
    end

    it "fails" do
      result = described_class.call(organization: organization)
      expect(result).to be_failure
      expect(result.error).to eq(:users_list_failed)
    end
  end
end
