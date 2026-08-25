require "rails_helper"

RSpec.describe AppMentionReplyJob do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }

  it "posts a threaded echo reply via the Slack client" do
    sender = instance_double(Slack::Request::SendMessage)
    allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)

    expect(sender).to receive(:send_message) do |channel, payload|
      expect(channel).to eq("C1")
      expect(payload[:thread_ts]).to eq("111.222")
      expect(payload[:text]).to include("hello there")
    end

    described_class.perform_now(
      team_id: workspace.identifier, channel: "C1", thread_ts: "111.222",
      user: "U1", text: "<@U0BOT> hello there",
    )
  end

  it "no-ops for an unknown team" do
    expect do
      described_class.perform_now(team_id: "T_NOPE", channel: "C1", thread_ts: "1", user: "U1", text: "hi")
    end.not_to raise_error
  end
end
