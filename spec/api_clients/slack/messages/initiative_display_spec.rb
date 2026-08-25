require "rails_helper"

RSpec.describe Slack::Messages::InitiativeDisplay do
  let(:goal) { create(:goal, title: "Grow activation") }
  let(:initiative) { create(:initiative, goal: goal, title: "Ship onboarding revamp", status: "proposed") }

  def buttons(initiative)
    described_class.new(initiative: initiative).to_h[:attachments].first[:blocks]
      .flat_map { |b| b[:elements] || [] }
      .select { |e| e[:type] == "button" }
  end

  it "includes an Edit initiative button carrying the initiative id" do
    button = buttons(initiative).find { |b| b[:action_id] == described_class::EDIT_ACTION_ID }

    expect(button[:value]).to eq(initiative.id.to_s)
    expect(described_class::EDIT_ACTION_ID).to eq("edit_initiative")
  end

  it "includes a danger Delete initiative button carrying the initiative id, with a native confirm dialog" do
    button = buttons(initiative).find { |b| b[:action_id] == described_class::DELETE_ACTION_ID }

    expect(described_class::DELETE_ACTION_ID).to eq("delete_initiative")
    expect(button[:value]).to eq(initiative.id.to_s)
    expect(button[:style]).to eq("danger")
    expect(button[:confirm][:style]).to eq("danger")
    expect(button[:confirm][:text][:text]).to include("Ship onboarding revamp")
    expect(button[:confirm][:confirm][:text]).to eq("Delete")
    expect(button[:confirm][:deny][:text]).to eq("Cancel")
  end
end
