require "rails_helper"

RSpec.describe Slack::Messages::GoalStartNotice do
  let(:organization) { create(:organization) }
  let(:owner) { create(:user, organization: organization, full_name: "Ada Lovelace") }
  let(:goal) do
    create(:goal, organization: organization, owners: [ owner ], title: "Grow activation",
                  start_date: "2026-08-20", end_date: "2026-09-20")
  end
  let!(:metric) { create(:metric, goal: goal, name: "Activation rate", direction: "increase", current_value: 20, target_value: 40, unit: "%") }

  it "renders the title, the metric target, and dates -- no LLM narrative" do
    payload = described_class.new(goal: goal).to_h

    expect(payload[:text]).to include("Grow activation")
    expect(payload[:blocks].to_s).to include("Grow activation")
    expect(payload[:blocks].to_s).to include("Activation rate").and include("20%").and include("40%")
    expect(payload[:blocks].to_s).to include("Aug 20").and include("Sep 20, 2026")
  end

  it "lists the owners" do
    payload = described_class.new(goal: goal).to_h

    expect(payload[:blocks].to_s).to include("Ada Lovelace")
  end

  it "omits the metric section when the goal has no metric" do
    bare_goal = create(:goal, organization: organization, owners: [ owner ], title: "No metric yet")

    payload = described_class.new(goal: bare_goal).to_h

    expect(payload[:blocks].to_s).not_to include("Target")
  end
end
