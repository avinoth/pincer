require "rails_helper"

RSpec.describe SendWelcomeMessageJob do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let!(:owner) { create(:user, :owner, organization: organization) }

  before { organization.update!(owner: owner) }

  it "DMs the owner via the Slack client" do
    sender = instance_double(Slack::Request::SendMessage)
    allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)

    expect(sender).to receive(:send_message).with(owner.provider_uid, hash_including(:text, :blocks))

    described_class.perform_now(organization.id)
  end

  it "stamps the owner's greeted_at after sending" do
    sender = instance_double(Slack::Request::SendMessage, send_message: nil)
    allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)

    expect(owner.greeted_at).to be_nil

    described_class.perform_now(organization.id)

    expect(owner.reload.greeted_at).to be_present
  end

  it "no-ops for a missing organization" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
