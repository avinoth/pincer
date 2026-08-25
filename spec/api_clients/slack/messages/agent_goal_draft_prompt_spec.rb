require "rails_helper"

RSpec.describe Slack::Messages::AgentGoalDraftPrompt do
  let(:agent_run) { create(:agent_run) }

  it "uses the agent-authored message as the text fallback and a section block" do
    payload = described_class.new(agent_run: agent_run, message: "Sounds like you want to grow activation.").to_h

    expect(payload[:text]).to eq("Sounds like you want to grow activation.")
    expect(payload[:blocks].first).to eq(
      type: "section",
      text: { type: "mrkdwn", text: "Sounds like you want to grow activation." },
    )
  end

  it "includes a Create Goal button carrying the agent_run id and the agent-specific action_id" do
    payload = described_class.new(agent_run: agent_run, message: "Draft ready.").to_h

    button = payload[:blocks].flat_map { |b| b[:elements] || [] }.find { |e| e[:type] == "button" }

    expect(button[:action_id]).to eq("agent_open_create_goal_modal")
    expect(button[:value]).to eq(agent_run.id.to_s)
    expect(button[:style]).to eq("primary")
    expect(described_class::ACTION_ID).to eq("agent_open_create_goal_modal")
  end
end
