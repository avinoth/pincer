require "rails_helper"

RSpec.describe Ai::Agent::Tools::PickInitiative do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:conversation) { create(:conversation, organization: organization, slack_channel_id: "C1") }
  let(:user) { create(:user, organization: organization) }
  let(:agent_run) { create(:agent_run, conversation: conversation) }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: agent_run)
  end
  let(:tool) { described_class.new(context) }
  let(:goal) { create(:goal, organization: organization) }

  let(:send_message) { instance_double(Slack::Request::SendMessage, send_message: nil) }

  before do
    allow(Slack::Request::SendMessage).to receive(:new).and_return(send_message)
  end

  context "with no matches" do
    it "returns an error asking the user to rephrase" do
      result = tool.execute(query: "nonexistent initiative")

      expect(result).to eq(error: "No initiative matches 'nonexistent initiative'. Ask the user to rephrase.")
      expect(send_message).not_to have_received(:send_message)
    end
  end

  context "with exactly one match" do
    it "resolves inline without pausing" do
      initiative = create(:initiative, goal: goal, title: "Ship onboarding revamp")

      result = tool.execute(query: "onboarding")

      expect(result).to eq(
        id: initiative.id, title: "Ship onboarding revamp", goal_id: goal.id, owner: nil, status: initiative.status
      )
      expect(send_message).not_to have_received(:send_message)
      expect(agent_run.reload.pending_tool_call).to be_nil
    end

    it "scopes the search to the given goal_id when provided" do
      other_goal = create(:goal, organization: organization)
      matching = create(:initiative, goal: goal, title: "Ship onboarding revamp")
      create(:initiative, goal: other_goal, title: "Ship onboarding revamp too")

      result = tool.execute(query: "onboarding", goal_id: goal.id)

      expect(result[:id]).to eq(matching.id)
    end
  end

  context "with more than 25 matches" do
    it "returns an error asking the user to narrow" do
      26.times { |i| create(:initiative, goal: goal, title: "Quarterly initiative #{i}") }

      result = tool.execute(query: "Quarterly")

      expect(result).to eq(error: "Too many initiatives match; ask the user to narrow.")
      expect(send_message).not_to have_received(:send_message)
    end
  end

  context "with 2-25 matches" do
    it "stashes candidate ids on pending_tool_call[\"args\"], posts a picker, and returns PENDING" do
      initiative_a = create(:initiative, goal: goal, title: "Ship onboarding revamp")
      initiative_b = create(:initiative, goal: goal, title: "Audit onboarding funnel")

      result = tool.execute(query: "onboarding")

      expect(result).to eq(Ai::Agent::Tools::PENDING)

      candidate_ids = agent_run.reload.pending_tool_call["args"]["candidate_initiative_ids"]
      expect(candidate_ids).to contain_exactly(initiative_a.id, initiative_b.id)

      expect(send_message).to have_received(:send_message) do |channel, payload|
        expect(channel).to eq("C1")
        expect(payload[:thread_ts]).to eq(conversation.slack_thread_ts)

        select = payload[:blocks].flat_map { |b| b[:elements] || [] }.find { |e| e[:type] == "static_select" }
        expect(select[:action_id]).to eq("agent_pick_initiative")
        option_values = select[:options].map { |o| o[:value] }
        expect(option_values).to contain_exactly(initiative_a.id.to_s, initiative_b.id.to_s)

        block_with_select = payload[:blocks].find { |b| b[:elements]&.any? { |e| e[:type] == "static_select" } }
        expect(block_with_select[:block_id]).to eq("agent_pick_initiative_#{agent_run.id}")
      end
    end

    it "merges candidate ids into any existing pending_tool_call rather than overwriting it" do
      agent_run.update!(pending_tool_call: { "id" => "call_123", "name" => "pick_initiative" })
      create(:initiative, goal: goal, title: "Ship onboarding revamp")
      create(:initiative, goal: goal, title: "Audit onboarding funnel")

      tool.execute(query: "onboarding")

      pending = agent_run.reload.pending_tool_call
      expect(pending["id"]).to eq("call_123")
      expect(pending["name"]).to eq("pick_initiative")
      expect(pending["args"]["candidate_initiative_ids"]).to be_present
    end
  end

  it "never leaks another organization's initiatives into the results" do
    create(:initiative, goal: create(:goal), title: "Grow activation initiative")

    result = tool.execute(query: "activation")

    expect(result).to eq(error: "No initiative matches 'activation'. Ask the user to rephrase.")
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(Initiative).to receive(:joins).and_raise(StandardError, "boom")

    result = tool.execute(query: "onboarding")

    expect(result).to eq(error: "Couldn't search initiatives for 'onboarding': boom")
  end
end
