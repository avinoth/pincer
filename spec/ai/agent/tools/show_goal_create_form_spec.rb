require "rails_helper"

RSpec.describe Ai::Agent::Tools::ShowGoalCreateForm do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:conversation) { create(:conversation, organization: organization, slack_channel_id: "C1") }
  let(:user) { create(:user, organization: organization) }
  let(:agent_run) { create(:agent_run, conversation: conversation) }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: agent_run)
  end
  let(:tool) { described_class.new(context) }

  let(:send_message) { instance_double(Slack::Request::SendMessage, send_message: nil) }

  before do
    allow(Slack::Request::SendMessage).to receive(:new).and_return(send_message)
  end

  it "persists the draft args onto agent_run.pending_tool_call[\"args\"]" do
    tool.execute(
      message: "Sounds like you want to grow activation this quarter.",
      title: "Grow activation",
      start_date: "2026-07-01",
      end_date: "2026-09-30",
      metric_name: "Activation rate",
      metric_direction: "increase",
      metric_target_value: 40,
      metric_unit: "%",
    )

    agent_run.reload
    args = agent_run.pending_tool_call["args"]

    expect(args["title"]).to eq("Grow activation")
    expect(args["start_date"]).to eq("2026-07-01")
    expect(args["end_date"]).to eq("2026-09-30")
    expect(args["metric_name"]).to eq("Activation rate")
    expect(args["metric_direction"]).to eq("increase")
    expect(args["metric_target_value"]).to eq(40)
    expect(args["metric_unit"]).to eq("%")
    expect(args).not_to have_key("description")
  end

  it "merges draft args into any existing pending_tool_call rather than overwriting it" do
    agent_run.update!(pending_tool_call: { "id" => "call_123", "name" => "show_goal_create_form" })

    tool.execute(message: "Draft ready.", title: "Grow activation")

    pending = agent_run.reload.pending_tool_call
    expect(pending["id"]).to eq("call_123")
    expect(pending["name"]).to eq("show_goal_create_form")
    expect(pending["args"]["title"]).to eq("Grow activation")
  end

  it "posts an AgentGoalDraftPrompt threaded in the conversation" do
    tool.execute(message: "Sounds like a new goal.", title: "Grow activation")

    expect(send_message).to have_received(:send_message) do |channel, payload|
      expect(channel).to eq("C1")
      expect(payload[:thread_ts]).to eq(conversation.slack_thread_ts)
      expect(payload[:text]).to eq("Sounds like a new goal.")

      button = payload[:blocks].flat_map { |b| b[:elements] || [] }.find { |e| e[:type] == "button" }
      expect(button[:action_id]).to eq("agent_open_create_goal_modal")
      expect(button[:value]).to eq(agent_run.id.to_s)
    end
  end

  it "returns the PENDING sentinel" do
    result = tool.execute(message: "Sounds like a new goal.", title: "Grow activation")

    expect(result).to eq(Ai::Agent::Tools::PENDING)
  end

  it "returns an error hash instead of raising when something goes wrong" do
    allow(agent_run).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(agent_run))

    result = tool.execute(message: "Sounds like a new goal.", title: "Grow activation")

    expect(result).to be_a(Hash)
    expect(result[:error]).to be_present
    expect(send_message).not_to have_received(:send_message)
  end
end
