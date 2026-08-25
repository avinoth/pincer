require "rails_helper"

RSpec.describe Ai::Agent::Tools::ShowGoal do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:conversation) { create(:conversation, organization: organization, slack_channel_id: "C1") }
  let(:user) { create(:user, organization: organization) }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: nil)
  end
  let(:tool) { described_class.new(context) }

  let(:send_message) { instance_double(Slack::Request::SendMessage, send_message: nil) }

  before do
    allow(Slack::Request::SendMessage).to receive(:new).and_return(send_message)
  end

  it "posts the GoalDisplay card threaded in the conversation" do
    goal = create(:goal, organization: organization, title: "Grow activation")

    tool.execute(goal_id: goal.id)

    expect(send_message).to have_received(:send_message) do |channel, payload|
      expect(channel).to eq("C1")
      expect(payload[:thread_ts]).to eq(conversation.slack_thread_ts)
      expect(payload).to eq(Slack::Messages::GoalDisplay.new(goal: goal).to_h.merge(thread_ts: conversation.slack_thread_ts))
    end
  end

  it "returns posted: true plus get_goal's full detail payload" do
    owner = create(:user, organization: organization, full_name: "Ada Lovelace")
    goal = create(:goal, organization: organization, title: "Grow activation", owners: [ owner ])
    create(:metric, goal: goal, name: "MRR", start_value: 0, current_value: 20, target_value: 40, unit: "%")

    result = tool.execute(goal_id: goal.id)

    expect(result[:posted]).to eq(true)
    expect(result[:id]).to eq(goal.id)
    expect(result[:title]).to eq("Grow activation")
    expect(result[:owners]).to eq([ "Ada Lovelace" ])
    expect(result[:metric]).to include(name: "MRR")
  end

  it "returns an error hash instead of raising when the goal isn't found in this organization" do
    other_org_goal = create(:goal)

    result = tool.execute(goal_id: other_org_goal.id)

    expect(result).to eq(error: "No goal found with id #{other_org_goal.id}.")
    expect(send_message).not_to have_received(:send_message)
  end

  it "returns an error hash instead of raising on internal failure" do
    goal = create(:goal, organization: organization)
    allow(send_message).to receive(:send_message).and_raise(StandardError, "slack down")

    result = tool.execute(goal_id: goal.id)

    expect(result).to eq(error: "Couldn't show goal #{goal.id}: slack down")
  end
end
