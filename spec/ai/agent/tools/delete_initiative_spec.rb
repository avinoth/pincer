require "rails_helper"

RSpec.describe Ai::Agent::Tools::DeleteInitiative do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:conversation) { create(:conversation, organization: organization, slack_channel_id: "C1") }
  let(:goal_creator) { create(:user, organization: organization, provider_uid: "U_CREATOR") }
  let(:goal) { create(:goal, organization: organization, creator: goal_creator) }
  let(:initiative_owner) { create(:user, organization: organization, provider_uid: "U_INIT_OWNER") }
  let(:initiative) do
    create(:initiative, goal: goal, owner: initiative_owner, title: "Ship onboarding revamp")
  end
  let(:user) { initiative_owner }
  let(:agent_run) { create(:agent_run, conversation: conversation) }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: agent_run)
  end
  let(:tool) { described_class.new(context) }

  let(:send_message) { instance_double(Slack::Request::SendMessage, send_message: nil) }

  before do
    allow(Slack::Request::SendMessage).to receive(:new).and_return(send_message)
  end

  it "persists the initiative_id onto agent_run.pending_tool_call[\"args\"] and returns PENDING, without deleting anything" do
    result = tool.execute(initiative_id: initiative.id, message: "Deleting 'Ship onboarding revamp' as requested.")

    expect(result).to eq(Ai::Agent::Tools::PENDING)
    expect(agent_run.reload.pending_tool_call["args"]).to eq("initiative_id" => initiative.id)
    expect(Initiative.exists?(initiative.id)).to be true
  end

  it "merges the args into any existing pending_tool_call rather than overwriting it" do
    agent_run.update!(pending_tool_call: { "id" => "call_1", "name" => "delete_initiative" })

    tool.execute(initiative_id: initiative.id, message: "Confirm delete?")

    pending = agent_run.reload.pending_tool_call
    expect(pending["id"]).to eq("call_1")
    expect(pending["name"]).to eq("delete_initiative")
    expect(pending["args"]).to eq("initiative_id" => initiative.id)
  end

  it "posts an AgentInitiativeDeletePrompt threaded in the conversation" do
    tool.execute(initiative_id: initiative.id, message: "Deleting 'Ship onboarding revamp' as requested.")

    expect(send_message).to have_received(:send_message) do |channel, payload|
      expect(channel).to eq("C1")
      expect(payload[:thread_ts]).to eq(conversation.slack_thread_ts)
      expect(payload[:text]).to eq("Deleting 'Ship onboarding revamp' as requested.")

      button = payload[:blocks].flat_map { |b| b[:elements] || [] }.find { |e| e[:type] == "button" }
      expect(button[:action_id]).to eq("agent_confirm_delete_initiative")
      expect(button[:value]).to eq(agent_run.id.to_s)
      expect(button[:style]).to eq("danger")
    end
  end

  it "returns an error, without posting or pausing, when the initiative isn't found in this organization" do
    other_org_initiative = create(:initiative)

    result = tool.execute(initiative_id: other_org_initiative.id, message: "Delete it")

    expect(result).to eq(error: "No initiative found with id #{other_org_initiative.id}.")
    expect(send_message).not_to have_received(:send_message)
    expect(agent_run.reload.pending_tool_call).to be_nil
  end

  it "rejects deletes from a user unrelated to the initiative or its goal, without pausing" do
    stranger = create(:user, organization: organization, provider_uid: "U_STRANGER")
    context_as_stranger = Ai::Agent::ToolContext.new(
      conversation: conversation, organization: organization, user: stranger, agent_run: agent_run,
    )

    result = described_class.new(context_as_stranger).execute(initiative_id: initiative.id, message: "Delete it")

    expect(result).to eq(error: "Only the initiative's owner or the goal's owners/creator can delete it.")
    expect(send_message).not_to have_received(:send_message)
    expect(agent_run.reload.pending_tool_call).to be_nil
    expect(Initiative.exists?(initiative.id)).to be true
  end

  it "allows the goal's creator (not just the initiative's owner) to trigger the confirm prompt" do
    context_as_creator = Ai::Agent::ToolContext.new(
      conversation: conversation, organization: organization, user: goal_creator, agent_run: agent_run,
    )

    result = described_class.new(context_as_creator).execute(initiative_id: initiative.id, message: "Delete it")

    expect(result).to eq(Ai::Agent::Tools::PENDING)
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(agent_run).to receive(:update!).and_raise(StandardError, "boom")

    result = tool.execute(initiative_id: initiative.id, message: "Delete it")

    expect(result).to eq(error: "Couldn't show the delete confirmation for initiative #{initiative.id}: boom")
    expect(send_message).not_to have_received(:send_message)
  end
end
