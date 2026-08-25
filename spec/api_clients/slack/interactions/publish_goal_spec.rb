require "rails_helper"

RSpec.describe Slack::Interactions::PublishGoal do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization, identifier: "T1") }

  def payload(value:, user_id: "U1")
    {
      "type" => "block_actions",
      "team" => { "id" => "T1" },
      "user" => { "id" => user_id },
      "channel" => { "id" => "C1" },
      "container" => { "message_ts" => "111.222" },
      "actions" => [ { "action_id" => "publish_goal", "value" => value } ]
    }
  end

  it "publishes a draft goal and updates the origin message in place with the published GoalDisplay for the creator" do
    goal = create(:goal, organization: organization, title: "Grow activation", publishing_status: "draft")

    updater = instance_double(Slack::Request::UpdateMessage)
    allow(Slack::Request::UpdateMessage).to receive(:new).with(workspace).and_return(updater)
    expect(updater).to receive(:update_message) do |channel, ts, message|
      expect(channel).to eq("C1")
      expect(ts).to eq("111.222")
      expect(message).to eq(Slack::Messages::GoalDisplay.new(goal: goal.reload).to_h)

      buttons = message[:attachments].first[:blocks].flat_map { |b| Array(b[:elements]) }.select { |e| e[:type] == "button" }
      expect(buttons.map { |b| b[:action_id] }).to eq([ "edit_goal" ])
    end

    described_class.new(payload(value: goal.id.to_s, user_id: goal.creator.provider_uid)).call

    expect(goal.reload).to be_publishing_published
  end

  it "publishes a draft goal for a goal owner" do
    goal = create(:goal, organization: organization, publishing_status: "draft")
    owner = create(:user, organization: organization)
    goal.owners = [ owner ]

    allow(Slack::Request::UpdateMessage).to receive(:new).and_return(instance_double(Slack::Request::UpdateMessage, update_message: nil))

    described_class.new(payload(value: goal.id.to_s, user_id: owner.provider_uid)).call

    expect(goal.reload).to be_publishing_published
  end

  it "does nothing when the goal is already published" do
    goal = create(:goal, organization: organization, publishing_status: "published")

    allow(Slack::Request::UpdateMessage).to receive(:new)

    described_class.new(payload(value: goal.id.to_s, user_id: goal.creator.provider_uid)).call

    expect(Slack::Request::UpdateMessage).not_to have_received(:new)
  end

  it "does nothing for a missing goal" do
    allow(Slack::Request::UpdateMessage).to receive(:new)

    described_class.new(payload(value: "0")).call

    expect(Slack::Request::UpdateMessage).not_to have_received(:new)
  end

  it "sends an ephemeral denial and leaves the goal in draft for an unauthorized user" do
    goal = create(:goal, organization: organization, publishing_status: "draft")

    sender = instance_double(Slack::Request::SendMessage)
    allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
    expect(sender).to receive(:send_ephemeral) do |channel, user, message|
      expect(channel).to eq("C1")
      expect(user).to eq("U_UNRELATED")
      expect(message[:text]).to match(/creator or an owner/)
    end
    allow(Slack::Request::UpdateMessage).to receive(:new)

    described_class.new(payload(value: goal.id.to_s, user_id: "U_UNRELATED")).call

    expect(goal.reload).to be_publishing_draft
    expect(Slack::Request::UpdateMessage).not_to have_received(:new)
  end
end
