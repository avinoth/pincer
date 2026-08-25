require "rails_helper"

RSpec.describe Slack::Interactions::ShowGoalDetail do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization, identifier: "T1") }

  def payload(value:, user_id: "U1", thread_ts: nil)
    {
      "type" => "block_actions",
      "team" => { "id" => "T1" },
      "user" => { "id" => user_id },
      "channel" => { "id" => "C1" },
      "container" => { "message_ts" => "111.222" },
      "message" => { "ts" => "111.222", "thread_ts" => thread_ts }.compact,
      "actions" => [ { "action_id" => Slack::Messages::GoalSummaryList::VIEW_DETAIL_ACTION_ID, "value" => value } ]
    }
  end

  it "posts the detail card (GoalDisplay) in the channel/thread the click came from" do
    goal = create(:goal, organization: organization, title: "Grow activation")

    sender = instance_double(Slack::Request::SendMessage)
    allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
    expect(sender).to receive(:send_message) do |channel, message|
      expect(channel).to eq("C1")
      expect(message[:thread_ts]).to eq("9.9")
      expect(message).to eq(Slack::Messages::GoalDisplay.new(goal: goal).to_h.merge(thread_ts: "9.9"))
    end

    described_class.new(payload(value: goal.id.to_s, thread_ts: "9.9")).call
  end

  it "falls back to the origin message's own ts as the thread when the summary card isn't itself in a thread" do
    goal = create(:goal, organization: organization)

    sender = instance_double(Slack::Request::SendMessage)
    allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
    expect(sender).to receive(:send_message) do |_channel, message|
      expect(message[:thread_ts]).to eq("111.222")
    end

    described_class.new(payload(value: goal.id.to_s)).call
  end

  it "does nothing for a missing goal" do
    allow(Slack::Request::SendMessage).to receive(:new)

    described_class.new(payload(value: "0")).call

    expect(Slack::Request::SendMessage).not_to have_received(:new)
  end

  it "does nothing for an unregistered workspace" do
    allow(Slack::Request::SendMessage).to receive(:new)

    payload_for_unknown_team = payload(value: "1").merge("team" => { "id" => "T_UNKNOWN" })
    described_class.new(payload_for_unknown_team).call

    expect(Slack::Request::SendMessage).not_to have_received(:new)
  end
end
