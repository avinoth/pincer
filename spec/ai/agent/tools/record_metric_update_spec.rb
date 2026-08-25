require "rails_helper"

RSpec.describe Ai::Agent::Tools::RecordMetricUpdate do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:conversation) { create(:conversation, organization: organization, slack_channel_id: "C1") }
  let(:owner) { create(:user, organization: organization, provider_uid: "U_OWNER") }
  let(:goal) { create(:goal, organization: organization, owners: [ owner ], title: "Grow activation") }
  let!(:metric) do
    create(:metric, goal: goal, name: "Activation rate", start_value: 20, current_value: 20, target_value: 40, unit: "%")
  end
  let(:user) { owner }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: nil)
  end
  let(:tool) { described_class.new(context) }

  let(:send_message) { instance_double(Slack::Request::SendMessage, send_message: nil) }

  before do
    allow(Slack::Request::SendMessage).to receive(:new).and_return(send_message)
  end

  it "records a MetricUpdate, advances current_value, logs a GoalUpdate, and posts a refreshed card" do
    result = tool.execute(goal_id: goal.id, value: 30, note: "good week")

    expect(metric.reload.current_value).to eq(30)
    expect(MetricUpdate.sole.value).to eq(30)
    expect(MetricUpdate.sole.reported_by).to eq(owner)
    expect(GoalUpdate.sole).to be_kind_metric

    expect(result[:goal_id]).to eq(goal.id)
    expect(result[:current_value]).to eq(30)
    expect(result[:error]).to be_nil

    expect(send_message).to have_received(:send_message) do |channel, payload|
      expect(channel).to eq("C1")
      expect(payload[:thread_ts]).to eq(conversation.slack_thread_ts)
      expect(payload[:attachments].to_s).to include("Grow activation")
    end
  end

  it "links the GoalUpdate to an open checkin when checkin_id is given" do
    checkin = create(:checkin, organization: organization, user: owner, goal: goal)

    tool.execute(goal_id: goal.id, value: 30, checkin_id: checkin.id)

    expect(GoalUpdate.sole.checkin).to eq(checkin)
  end

  it "returns an error, without posting, when the goal isn't found in this organization" do
    other_org_goal = create(:goal)

    result = tool.execute(goal_id: other_org_goal.id, value: 30)

    expect(result).to eq(error: "No goal found with id #{other_org_goal.id}.")
    expect(send_message).not_to have_received(:send_message)
    expect(MetricUpdate.count).to eq(0)
  end

  it "returns an error when the goal has no metric" do
    metric.destroy!
    goal.reload

    result = tool.execute(goal_id: goal.id, value: 30)

    expect(result[:error]).to include("no metric")
    expect(send_message).not_to have_received(:send_message)
  end

  it "rejects a report from a user who is neither the creator nor an owner" do
    stranger = create(:user, organization: organization, provider_uid: "U_STRANGER")
    context_as_stranger = Ai::Agent::ToolContext.new(
      conversation: conversation, organization: organization, user: stranger, agent_run: nil
    )

    result = described_class.new(context_as_stranger).execute(goal_id: goal.id, value: 30)

    expect(result).to eq(error: "Only the goal's owners or creator can report a metric value.")
    expect(metric.reload.current_value).to eq(20)
    expect(send_message).not_to have_received(:send_message)
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(organization).to receive(:goals).and_raise(StandardError, "boom")

    result = tool.execute(goal_id: goal.id, value: 30)

    expect(result).to eq(error: "Couldn't record a metric update for goal #{goal.id}: boom")
  end
end
