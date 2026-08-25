require "rails_helper"

RSpec.describe Ai::Agent::Tools::ShowInitiativeCreateForm do
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
    goal = create(:goal, organization: organization)

    tool.execute(
      message: "Sounds like a new initiative under Grow activation.",
      goal_id: goal.id,
      title: "Ship onboarding revamp",
      owner: "U_OWNER",
    )

    agent_run.reload
    args = agent_run.pending_tool_call["args"]

    expect(args["goal_id"]).to eq(goal.id)
    expect(args["title"]).to eq("Ship onboarding revamp")
    expect(args["owner"]).to eq("U_OWNER")
    expect(args).not_to have_key("description")
  end

  it "merges draft args into any existing pending_tool_call rather than overwriting it" do
    agent_run.update!(pending_tool_call: { "id" => "call_123", "name" => "show_initiative_create_form" })

    tool.execute(message: "Draft ready.", title: "Ship onboarding revamp")

    pending = agent_run.reload.pending_tool_call
    expect(pending["id"]).to eq("call_123")
    expect(pending["name"]).to eq("show_initiative_create_form")
    expect(pending["args"]["title"]).to eq("Ship onboarding revamp")
  end

  it "posts an AgentInitiativeDraftPrompt threaded in the conversation" do
    tool.execute(message: "Sounds like a new initiative.", title: "Ship onboarding revamp")

    expect(send_message).to have_received(:send_message) do |channel, payload|
      expect(channel).to eq("C1")
      expect(payload[:thread_ts]).to eq(conversation.slack_thread_ts)
      expect(payload[:text]).to eq("Sounds like a new initiative.")

      button = payload[:blocks].flat_map { |b| b[:elements] || [] }.find { |e| e[:type] == "button" }
      expect(button[:action_id]).to eq("agent_open_create_initiative_modal")
      expect(button[:value]).to eq(agent_run.id.to_s)
    end
  end

  it "returns the PENDING sentinel" do
    result = tool.execute(message: "Sounds like a new initiative.", title: "Ship onboarding revamp")

    expect(result).to eq(Ai::Agent::Tools::PENDING)
  end

  it "returns an error hash instead of raising when something goes wrong" do
    allow(agent_run).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(agent_run))

    result = tool.execute(message: "Sounds like a new initiative.", title: "Ship onboarding revamp")

    expect(result).to be_a(Hash)
    expect(result[:error]).to be_present
    expect(send_message).not_to have_received(:send_message)
  end
end
