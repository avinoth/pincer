require "rails_helper"

RSpec.describe Ai::Agent::Tools::PickGoal do
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

  context "with no matches" do
    it "returns an error asking the user to rephrase" do
      result = tool.execute(query: "nonexistent goal")

      expect(result).to eq(error: "No goal matches 'nonexistent goal'. Ask the user to rephrase.")
      expect(send_message).not_to have_received(:send_message)
    end
  end

  context "with exactly one match" do
    it "resolves inline without pausing" do
      goal = create(:goal, organization: organization, title: "Grow activation",
        start_date: "2026-08-01", end_date: "2026-09-01")

      result = tool.execute(query: "activation")

      expect(result).to eq(
        id: goal.id, title: "Grow activation", start_date: goal.start_date, end_date: goal.end_date,
        status: goal.status
      )
      expect(send_message).not_to have_received(:send_message)
      expect(agent_run.reload.pending_tool_call).to be_nil
    end
  end

  context "with more than 25 matches" do
    it "returns an error asking the user to narrow" do
      26.times { |i| create(:goal, organization: organization, title: "Quarterly goal #{i}") }

      result = tool.execute(query: "Quarterly")

      expect(result).to eq(error: "Too many goals match; ask the user to narrow.")
      expect(send_message).not_to have_received(:send_message)
    end
  end

  context "with 2-25 matches" do
    it "stashes candidate ids on pending_tool_call[\"args\"], posts a picker, and returns PENDING" do
      goal_a = create(:goal, organization: organization, title: "Grow activation")
      goal_b = create(:goal, organization: organization, title: "Grow revenue activation")

      result = tool.execute(query: "activation")

      expect(result).to eq(Ai::Agent::Tools::PENDING)

      candidate_ids = agent_run.reload.pending_tool_call["args"]["candidate_goal_ids"]
      expect(candidate_ids).to contain_exactly(goal_a.id, goal_b.id)

      expect(send_message).to have_received(:send_message) do |channel, payload|
        expect(channel).to eq("C1")
        expect(payload[:thread_ts]).to eq(conversation.slack_thread_ts)

        select = payload[:blocks].flat_map { |b| b[:elements] || [] }.find { |e| e[:type] == "static_select" }
        expect(select[:action_id]).to eq("agent_pick_goal")
        option_values = select[:options].map { |o| o[:value] }
        expect(option_values).to contain_exactly(goal_a.id.to_s, goal_b.id.to_s)

        block_with_select = payload[:blocks].find { |b| b[:elements]&.any? { |e| e[:type] == "static_select" } }
        expect(block_with_select[:block_id]).to eq("agent_pick_goal_#{agent_run.id}")
      end
    end

    it "merges candidate ids into any existing pending_tool_call rather than overwriting it" do
      agent_run.update!(pending_tool_call: { "id" => "call_123", "name" => "pick_goal" })
      create(:goal, organization: organization, title: "Grow activation")
      create(:goal, organization: organization, title: "Grow revenue activation")

      tool.execute(query: "activation")

      pending = agent_run.reload.pending_tool_call
      expect(pending["id"]).to eq("call_123")
      expect(pending["name"]).to eq("pick_goal")
      expect(pending["args"]["candidate_goal_ids"]).to be_present
    end
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(organization).to receive(:goals).and_raise(StandardError, "boom")

    result = tool.execute(query: "activation")

    expect(result).to eq(error: "Couldn't search goals for 'activation': boom")
  end
end
