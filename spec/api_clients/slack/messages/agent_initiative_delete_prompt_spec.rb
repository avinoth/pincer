require "rails_helper"

RSpec.describe Slack::Messages::AgentInitiativeDeletePrompt do
  let(:agent_run) { create(:agent_run) }
  let(:initiative) { create(:initiative, title: "Ship onboarding revamp") }

  it "uses the agent-authored message as the text fallback and a section block" do
    payload = described_class.new(agent_run: agent_run, message: "Deleting 'Ship onboarding revamp'.", initiative: initiative).to_h

    expect(payload[:text]).to eq("Deleting 'Ship onboarding revamp'.")
    expect(payload[:blocks].first).to eq(
      type: "section",
      text: { type: "mrkdwn", text: "Deleting 'Ship onboarding revamp'." },
    )
  end

  it "includes a danger Delete initiative button carrying the agent_run id and the agent-specific action_id" do
    payload = described_class.new(agent_run: agent_run, message: "Confirm?", initiative: initiative).to_h

    button = payload[:blocks].flat_map { |b| b[:elements] || [] }.find { |e| e[:type] == "button" }

    expect(button[:action_id]).to eq("agent_confirm_delete_initiative")
    expect(button[:value]).to eq(agent_run.id.to_s)
    expect(button[:style]).to eq("danger")
    expect(described_class::ACTION_ID).to eq("agent_confirm_delete_initiative")
  end
end
