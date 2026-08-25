require "rails_helper"

RSpec.describe Slack::Messages::GoalSummary do
  let(:organization) { create(:organization) }
  let(:owner) { create(:user, organization: organization) }
  let(:goal) { create(:goal, organization: organization, owners: [ owner ], title: "Grow activation") }
  let!(:metric) { create(:metric, goal: goal, name: "Activation rate", direction: "increase", current_value: 32, target_value: 40, unit: "%") }

  it "renders the health badge, the narrative body, and the metric line for a weekly summary" do
    payload = described_class.new(goal: goal, health: "on_track", body: "Great week overall.", mode: :weekly).to_h

    expect(payload[:text]).to include("Weekly summary").and include("Grow activation")
    expect(payload[:attachments].first[:blocks].to_s).to include("Great week overall.")
    expect(payload[:attachments].first[:blocks].to_s).to include("On track")
    expect(payload[:attachments].first[:blocks].to_s).to include("Activation rate").and include("32%").and include("40%")
  end

  it "renders a closing heading for mode: :end" do
    payload = described_class.new(goal: goal, health: "at_risk", body: "Missed the target.", mode: :end).to_h

    expect(payload[:text]).to include("Goal cycle complete")
    expect(payload[:attachments].first[:blocks].to_s).to include("At risk")
  end

  it "colors the attachment by health" do
    payload = described_class.new(goal: goal, health: "off_track", body: "Behind.", mode: :weekly).to_h

    expect(payload[:attachments].first[:color]).to eq(Slack::GoalCardPresenter::HEALTH_COLORS["off_track"])
  end
end
